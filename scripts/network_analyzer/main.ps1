#Requires -Version 5.1
<#
.SYNOPSIS
    Network Analyzer — 네트워크 구간별 연결 상태 모니터링 및 장애 분석
.NOTES
    실행: powershell -ExecutionPolicy Bypass -File ".\main.ps1"
    로그: .\\_network_analyzer_logs\\YYYYMMDD_HHMMSS\\
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── ANSI colors ───────────────────────────────────────────────────────────────
$ESC    = [char]27
$CYAN   = "$ESC[36m"
$GREEN  = "$ESC[32m"
$YELLOW = "$ESC[33m"
$RED    = "$ESC[31m"
$GRAY   = "$ESC[90m"
$BOLD   = "$ESC[1m"
$NC     = "$ESC[0m"

# ── Visible width helper ──────────────────────────────────────────────────────
function Get-VisibleWidth([string]$text) {
    $plain = $text -replace '\x1b\[[0-9;]*m', ''
    $w = 0
    foreach ($c in $plain.ToCharArray()) {
        $cp = [int][char]$c
        if (($cp -ge 0x1100 -and $cp -le 0x115F) -or
            ($cp -ge 0x2E80 -and $cp -le 0x303F) -or
            ($cp -ge 0x3040 -and $cp -le 0x33FF) -or
            ($cp -ge 0x3400 -and $cp -le 0x4DBF) -or
            ($cp -ge 0x4E00 -and $cp -le 0x9FFF) -or
            ($cp -ge 0xAC00 -and $cp -le 0xD7AF) -or
            ($cp -ge 0xF900 -and $cp -le 0xFAFF) -or
            ($cp -ge 0xFF01 -and $cp -le 0xFF60) -or
            ($cp -ge 0xFFE0 -and $cp -le 0xFFE6)) {
            $w += 2
        } else {
            $w += 1
        }
    }
    return $w
}

# ── Script-scope state ────────────────────────────────────────────────────────
$script:Targets      = @()   # array of hashtable (target data)
$script:Events       = @()   # array of hashtable (incident events)
$script:DnsQuery     = @{ Domain=''; DnsIp=''; Sent=0; Received=0; TotalMs=0; LastStatus=''; LastMs=0 }
$script:LogDir       = ''
$script:TimelineFile = ''
$script:StartTime    = $null
$script:ReportWritten = $false

# ── Helpers ───────────────────────────────────────────────────────────────────
function Test-ValidIp([string]$ip) {
    if ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { return $false }
    foreach ($octet in $ip -split '\.') {
        if ([int]$octet -gt 255) { return $false }
    }
    return $true
}

function Read-RequiredIp([string]$prompt) {
    while ($true) {
        $value = (Read-Host $prompt).Trim()
        if ($value -eq '') {
            Write-Host "${RED}IP 주소를 입력하세요.${NC}"
            continue
        }
        if (-not (Test-ValidIp $value)) {
            Write-Host "${RED}올바른 IP 형식이 아닙니다 (예: 192.168.1.1)${NC}"
            continue
        }
        return $value
    }
}

function Read-OptionalTarget([string]$prompt) {
    while ($true) {
        $value = (Read-Host $prompt).Trim()
        if ($value -eq '') { return $null }

        $parts = $value -split '\s+', 2
        if ($parts.Count -ne 2) {
            Write-Host "${RED}레이블과 IP를 공백으로 구분해서 입력하세요 (예: Internet 8.8.8.8)${NC}"
            continue
        }
        if (-not (Test-ValidIp $parts[1])) {
            Write-Host "${RED}올바른 IP 형식이 아닙니다 (예: Internet 8.8.8.8)${NC}"
            continue
        }
        return @{ Label = $parts[0]; IP = $parts[1] }
    }
}

function New-Target([string]$name, [string]$role, [string]$ip) {
    return @{
        Name       = $name
        Role       = $role
        IP         = $ip
        Sent       = 0
        Received   = 0
        TotalMs    = 0
        MinMs      = [int]::MaxValue
        MaxMs      = 0
        ConsecFail = 0
        LastStatus = ''
        LastMs     = 0
    }
}

# ── Input collection ──────────────────────────────────────────────────────────
function Invoke-InputCollection {
    Write-Host "`n${BOLD}${CYAN}Network Connectivity Analyzer${NC}`n"
    Write-Host "${GRAY}네트워크 구간별 연결 상태를 모니터링하고 장애를 분석합니다.${NC}`n"

    $gwIp  = Read-RequiredIp  '  [1] Gateway IP     (필수, 예: 192.168.1.1)'
    $dnsIp = Read-RequiredIp  '  [2] DNS IP         (필수, 예: 8.8.8.1)'

    $domainInput = (Read-Host '  [3] DNS 쿼리 도메인  (기본: google.com, Enter로 스킵)').Trim()
    $dnsDomain   = if ($domainInput -eq '') { 'google.com' } else { $domainInput }

    Write-Host ''
    $opt1 = Read-OptionalTarget '  [4] 추가 대상 #1    (예: Internet 8.8.8.8, Enter로 스킵)'
    $opt2 = Read-OptionalTarget '  [5] 추가 대상 #2    (예: InternalSrv 10.0.0.100, Enter로 스킵)'
    Write-Host ''

    $script:Targets = @(
        (New-Target 'Gateway' 'GW'  $gwIp),
        (New-Target 'DNS'     'DNS' $dnsIp)
    )
    if ($opt1) { $script:Targets += New-Target $opt1.Label 'Custom1' $opt1.IP }
    if ($opt2) { $script:Targets += New-Target $opt2.Label 'Custom2' $opt2.IP }

    $script:DnsQuery.Domain = $dnsDomain
    $script:DnsQuery.DnsIp  = $dnsIp
}

# ── Log directory setup ───────────────────────────────────────────────────────
function Initialize-LogDir {
    $scriptDir  = $PSScriptRoot
    $timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
    $logRoot    = Join-Path $scriptDir '_network_analyzer_logs'
    $script:LogDir       = Join-Path $logRoot $timestamp
    $script:TimelineFile = Join-Path $script:LogDir 'timeline.txt'

    $null = New-Item -ItemType Directory -Path $script:LogDir -Force

    $header = @(
        ('Network Analyzer - Timeline Log'),
        ('Start: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')),
        ('Targets: {0}' -f (($script:Targets | ForEach-Object { '{0} ({1})' -f $_.Name, $_.IP }) -join ', ')),
        ('DNS Query: {0} via {1}' -f $script:DnsQuery.Domain, $script:DnsQuery.DnsIp),
        ('-' * 72)
    )
    $header | Set-Content -LiteralPath $script:TimelineFile -Encoding UTF8

    Write-Host "${GREEN}로그 폴더: $($script:LogDir)${NC}"
}

# ── Write-TimelineLog ─────────────────────────────────────────────────────────
function Write-TimelineLog([string]$type, [string]$target, [string]$message) {
    $ts   = Get-Date -Format 'HH:mm:ss.fff'
    $line = '[{0}] [{1,-5}] [{2,-12}] {3}' -f $ts, $type, $target, $message
    Add-Content -LiteralPath $script:TimelineFile -Value $line -Encoding UTF8
}

# ── ICMP probe ────────────────────────────────────────────────────────────────
function Test-IcmpTarget([hashtable]$target) {
    $target.Sent++
    try {
        $reply = Test-Connection -ComputerName $target.IP -Count 1 -ErrorAction Stop |
                 Select-Object -First 1
        $ms  = [int]$reply.ResponseTime
        $ttl = $reply.TimeToLive

        $target.Received++
        $target.TotalMs    += $ms
        $target.LastMs      = $ms
        $target.LastStatus  = 'OK'
        $target.ConsecFail  = 0
        if ($ms -lt $target.MinMs) { $target.MinMs = $ms }
        if ($ms -gt $target.MaxMs) { $target.MaxMs = $ms }

        Write-TimelineLog 'PING' $target.Name ('OK   {0,4}ms TTL={1}' -f $ms, $ttl)
    }
    catch {
        $target.LastStatus = 'FAIL'
        $target.LastMs     = 0
        $target.ConsecFail++

        $errMsg = $_.Exception.Message -replace '\r?\n', ' '
        Write-TimelineLog 'PING' $target.Name ('FAIL {0}' -f $errMsg)

        if ($target.ConsecFail -eq 3) {
            $diag = Get-SegmentDiagnosis
            $eventLine = 'FAIL 연속 {0}회 | {1}' -f $target.ConsecFail, $diag
            Write-TimelineLog 'EVENT' $target.Name $eventLine
            $script:Events += @{
                Time    = Get-Date
                Target  = $target.Name
                IP      = $target.IP
                Count   = $target.ConsecFail
                Diag    = $diag
                Ongoing = $true
            }
        } elseif ($target.ConsecFail -gt 3 -and $script:Events.Count -gt 0) {
            $last = $script:Events[-1]
            if ($last.Target -eq $target.Name -and $last.Ongoing) {
                $last.Count = $target.ConsecFail
            }
        }
    }

    if ($target.ConsecFail -eq 0 -and $script:Events.Count -gt 0) {
        $last = $script:Events[-1]
        if ($last.Target -eq $target.Name -and $last.Ongoing) {
            $last.Ongoing  = $false
            $last.EndTime  = Get-Date
        }
    }

    if ($script:Events.Count -gt 100) {
        $script:Events = $script:Events[-100..-1]
    }
}

# ── DNS probe ─────────────────────────────────────────────────────────────────
function Test-DnsQuery {
    $dq = $script:DnsQuery
    $dq.Sent++
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        $null = Resolve-DnsName -Name $dq.Domain -Server $dq.DnsIp -ErrorAction Stop
        $sw.Stop()
        $ms = [int]$sw.Elapsed.TotalMilliseconds

        $dq.Received++
        $dq.TotalMs   += $ms
        $dq.LastMs     = $ms
        $dq.LastStatus = 'OK'

        Write-TimelineLog 'DNS' $dq.Domain ('OK   {0,4}ms via {1}' -f $ms, $dq.DnsIp)
    }
    catch {
        $sw.Stop()
        $dq.LastStatus = 'FAIL'
        $dq.LastMs     = 0
        $errMsg = $_.Exception.Message -replace '\r?\n', ' '
        Write-TimelineLog 'DNS' $dq.Domain ('FAIL {0}' -f $errMsg)
    }
}

# ── Traceroute ────────────────────────────────────────────────────────────────
function Invoke-Traceroute {
    $traceFile = Join-Path $script:LogDir 'traceroute.txt'
    $lines     = @('Network Analyzer - Traceroute Results', ('Time: {0}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')), '')
    $lines | Set-Content -LiteralPath $traceFile -Encoding UTF8

    foreach ($target in $script:Targets) {
        Write-Host "  ${GRAY}traceroute: $($target.Name) ($($target.IP))...${NC}"
        Write-TimelineLog 'TRACE' $target.Name ('traceroute 시작 → {0}' -f $target.IP)

        $header = '=== {0} ({1}) ===' -f $target.Name, $target.IP
        Add-Content -LiteralPath $traceFile -Value $header -Encoding UTF8

        try {
            $raw = & tracert -d -w 3000 $target.IP 2>&1
            $raw | ForEach-Object { Add-Content -LiteralPath $traceFile -Value $_ -Encoding UTF8 }
            Add-Content -LiteralPath $traceFile -Value '' -Encoding UTF8

            $hopLines = $raw | Where-Object { $_ -match '^\s+\d+' }
            $hopCount = 0
            foreach ($hopLine in $hopLines) {
                $parts  = ($hopLine.Trim() -split '\s+')
                $hopNum = $parts[0]
                $hopIp  = $parts[-1]
                if ($hopIp -match '\d{1,3}(\.\d{1,3}){3}') {
                    $hopCount++
                    Write-TimelineLog 'TRACE' $target.Name ('hop {0}: {1}' -f $hopNum, $hopIp)
                }
            }
            if ($hopCount -eq 0) {
                Write-TimelineLog 'TRACE' $target.Name 'no hops resolved'
            }
        }
        catch {
            Add-Content -LiteralPath $traceFile -Value ('ERROR: {0}' -f $_.Exception.Message) -Encoding UTF8
            Write-TimelineLog 'TRACE' $target.Name ('traceroute failed: {0}' -f $_.Exception.Message)
        }
    }

    Write-Host ''
}

# ── Segment diagnosis ─────────────────────────────────────────────────────────
function Get-SegmentDiagnosis {
    $gw  = $script:Targets | Where-Object { $_.Role -eq 'GW'  } | Select-Object -First 1
    $dns = $script:Targets | Where-Object { $_.Role -eq 'DNS' } | Select-Object -First 1
    $net = $script:Targets | Where-Object { $_.Role -eq 'Custom1' } | Select-Object -First 1
    $srv = $script:Targets | Where-Object { $_.Role -eq 'Custom2' } | Select-Object -First 1

    $gwOk  = $gw  -and $gw.LastStatus  -eq 'OK'
    $dnsOk = $dns -and $dns.LastStatus -eq 'OK'
    $netOk = $net -and $net.LastStatus -eq 'OK'
    $srvOk = $srv -and $srv.LastStatus -eq 'OK'

    if (-not $gwOk) { return 'GW:FAIL — 로컬 네트워크 / 게이트웨이 문제' }
    if ($gwOk -and -not $dnsOk) { return 'GW:OK DNS:FAIL — DNS 서버 문제' }
    if ($net -and $gwOk -and $dnsOk -and -not $netOk) { return 'GW:OK DNS:OK Net:FAIL — ISP / 업스트림 라우팅 문제' }
    if ($srv -and $gwOk -and $dnsOk -and (-not $net -or $netOk) -and -not $srvOk) { return 'GW:OK DNS:OK — 사내 서버 문제' }
    return '정상'
}

# ── Dashboard ─────────────────────────────────────────────────────────────────
function Show-Dashboard {
    $elapsed = (Get-Date) - $script:StartTime
    $elapsedStr = '{0:D2}:{1:D2}:{2:D2}' -f [int]$elapsed.TotalHours, $elapsed.Minutes, $elapsed.Seconds
    $startStr   = $script:StartTime.ToString('yyyy-MM-dd HH:mm:ss')

    $w = 72
    $border = '═' * $w
    $sep    = '─' * $w

    [Console]::Clear()

    Write-Host "${CYAN}╔${border}╗${NC}"
    Write-Host "${CYAN}║${NC}  ${BOLD}Network Connectivity Analyzer${NC}$((' ' * ($w - 32)))${CYAN}║${NC}"
    Write-Host "${CYAN}║${NC}  Started: ${startStr}        Elapsed: ${elapsedStr}$((' ' * ($w - 55)))${CYAN}║${NC}"
    Write-Host "${CYAN}╠${border}╣${NC}"

    $hdr = '  {0,-14} {1,-16} {2,-6} {3,-8} {4,-7} {5}' -f 'TARGET','IP','STATUS','LATENCY','LOSS%','SENT'
    Write-Host "${CYAN}║${NC}${hdr}$((' ' * ($w - $hdr.Length)))${CYAN}║${NC}"

    foreach ($t in $script:Targets) {
        $loss = if ($t.Sent -gt 0) { '{0:N1}%' -f (($t.Sent - $t.Received) / $t.Sent * 100) } else { '---' }
        $lat  = if ($t.LastStatus -eq 'OK') { '{0}ms' -f $t.LastMs } else { '---' }

        if ($t.LastStatus -eq 'OK') {
            $statusStr = "${GREEN}● OK  ${NC}"
        } elseif ($t.LastStatus -eq 'FAIL') {
            $statusStr = "${RED}✗ FAIL${NC}"
        } else {
            $statusStr = "${GRAY}○ ----${NC}"
        }

        $namePad = '{0,-14}' -f ($t.Name.Substring(0, [Math]::Min($t.Name.Length, 13)))
        $ipPad   = '{0,-16}' -f $t.IP
        $latPad  = '{0,-8}' -f $lat
        $lossPad = '{0,-7}' -f $loss
        $sentStr = '{0}' -f $t.Sent

        $row = '  ' + $namePad + ' ' + $ipPad + ' ' + $statusStr + ' ' + $latPad + ' ' + $lossPad + ' ' + $sentStr
        $visLen = 2 + 14 + 1 + 16 + 1 + 6 + 1 + 8 + 1 + 7 + 1 + $sentStr.Length
        Write-Host "${CYAN}║${NC}${row}$((' ' * ($w - $visLen)))${CYAN}║${NC}"
    }

    Write-Host "${CYAN}╠${border}╣${NC}"

    $dq = $script:DnsQuery
    if ($dq.Sent -gt 0) {
        $dqLat  = if ($dq.LastStatus -eq 'OK') { '{0}ms' -f $dq.LastMs } else { '---' }
        if ($dq.LastStatus -eq 'OK') {
            $dqStat = "${GREEN}● OK${NC}"
        } else {
            $dqStat = "${RED}✗ FAIL${NC}"
        }
        $dqRow = '  DNS Query  {0,-20} {1}  {2}  ({3}회 테스트)' -f $dq.Domain, $dqStat, $dqLat, $dq.Sent
        Write-Host "${CYAN}║${NC}${dqRow}$((' ' * ($w - (Get-VisibleWidth $dqRow))))${CYAN}║${NC}"
    } else {
        $dqRow = '  DNS Query  대기 중...'
        Write-Host "${CYAN}║${NC}${dqRow}$((' ' * ($w - (Get-VisibleWidth $dqRow))))${CYAN}║${NC}"
    }

    Write-Host "${CYAN}╠${border}╣${NC}"

    $diag    = Get-SegmentDiagnosis
    $diagCol = if ($diag -eq '정상') { $GRAY } else { $YELLOW }
    $diagRow = '  SEGMENT DIAGNOSIS: ' + $diag
    Write-Host "${CYAN}║${NC}${diagCol}${diagRow}${NC}$((' ' * ($w - (Get-VisibleWidth $diagRow))))${CYAN}║${NC}"

    Write-Host "${CYAN}╠${border}╣${NC}"

    $evtHeader = '  RECENT EVENTS (최근 5건)'
    Write-Host "${CYAN}║${NC}${evtHeader}$((' ' * ($w - (Get-VisibleWidth $evtHeader))))${CYAN}║${NC}"

    $recentEvents = @(if ($script:Events.Count -gt 0) { $script:Events[-([Math]::Min($script:Events.Count, 5))..-1] | Sort-Object { $_.Time } -Descending })

    for ($i = 0; $i -lt 5; $i++) {
        if ($i -lt $recentEvents.Count) {
            $ev      = $recentEvents[$i]
            $ts      = $ev.Time.ToString('HH:mm:ss')
            $ongoing = if ($ev.Ongoing) { ' (진행 중)' } else { '' }
            $evRow   = '  [{0}] {1} ({2}) FAIL {3}회{4}' -f $ts, $ev.Target, $ev.IP, $ev.Count, $ongoing
            $evRow   = if ((Get-VisibleWidth $evRow) -gt $w) { $evRow.Substring(0, $w) } else { $evRow }
            Write-Host "${CYAN}║${NC}${YELLOW}${evRow}${NC}$((' ' * ($w - (Get-VisibleWidth $evRow))))${CYAN}║${NC}"
        } else {
            Write-Host "${CYAN}║${NC}$((' ' * $w))${CYAN}║${NC}"
        }
    }

    Write-Host "${CYAN}╚${border}╝${NC}"
    Write-Host "  ${GRAY}Ctrl+C 또는 창 닫기 → 모니터링 종료 후 리포트 자동 생성${NC}"
}

# ── Summary report ────────────────────────────────────────────────────────────
function New-SummaryReport {
    if ($script:ReportWritten) { return }
    $script:ReportWritten = $true

    $endTime  = Get-Date
    $duration = $endTime - $script:StartTime
    $durStr   = '{0}분 {1}초' -f [int]$duration.TotalMinutes, $duration.Seconds
    $maxSent  = ($script:Targets | Measure-Object -Property Sent -Maximum).Maximum

    $reportFile = Join-Path $script:LogDir 'report.txt'
    $sb = [System.Text.StringBuilder]::new()

    $null = $sb.AppendLine('=' * 60)
    $null = $sb.AppendLine('  Network Connectivity Analysis Report')
    $null = $sb.AppendLine('=' * 60)
    $null = $sb.AppendLine('  기간  : {0} ~ {1}' -f $script:StartTime.ToString('yyyy-MM-dd HH:mm:ss'), $endTime.ToString('HH:mm:ss'))
    $null = $sb.AppendLine('  소요  : {0}' -f $durStr)
    $null = $sb.AppendLine('  샘플  : {0}회' -f $maxSent)
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('TARGET 통계:')

    foreach ($t in $script:Targets) {
        $pct    = if ($t.Sent -gt 0) { '{0:N1}' -f ($t.Received / $t.Sent * 100) } else { '0.0' }
        $avg    = if ($t.Received -gt 0) { '{0}ms' -f [int]($t.TotalMs / $t.Received) } else { '---' }
        $minMs  = if ($t.MinMs -eq [int]::MaxValue) { '---' } else { '{0}ms' -f $t.MinMs }
        $maxMs  = if ($t.MaxMs -gt 0) { '{0}ms' -f $t.MaxMs } else { '---' }
        $null = $sb.AppendLine('  {0,-14} {1,-16} {2}/{3} ({4}%)  avg={5}  min={6}  max={7}' -f `
            $t.Name, $t.IP, $t.Received, $t.Sent, $pct, $avg, $minMs, $maxMs)
    }

    $dq = $script:DnsQuery
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('DNS 쿼리 ({0} via {1}):' -f $dq.Domain, $dq.DnsIp)
    if ($dq.Sent -gt 0) {
        $dqPct = '{0:N1}' -f ($dq.Received / $dq.Sent * 100)
        $dqAvg = if ($dq.Received -gt 0) { '{0}ms' -f [int]($dq.TotalMs / $dq.Received) } else { '---' }
        $null = $sb.AppendLine('  성공: {0}/{1} ({2}%)  avg={3}' -f $dq.Received, $dq.Sent, $dqPct, $dqAvg)
    } else {
        $null = $sb.AppendLine('  테스트 없음 (10초 미만 실행)')
    }

    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('장애 이벤트:')
    $incidents = $script:Events | Where-Object { -not $_.Ongoing -or $_.Count -ge 3 }
    if ($incidents -and @($incidents).Count -gt 0) {
        foreach ($ev in $incidents) {
            $endLabel = if ($ev.Ongoing) { '진행 중' } elseif ($ev.EndTime) { $ev.EndTime.ToString('HH:mm:ss') } else { '---' }
            $null = $sb.AppendLine('  {0} ~ {1}  {2} ({3})  연속 {4}회  [{5}]' -f `
                $ev.Time.ToString('HH:mm:ss'), $endLabel, $ev.Target, $ev.IP, $ev.Count, $ev.Diag)
        }
    } else {
        $null = $sb.AppendLine('  장애 이벤트 없음')
    }

    $segmentCounts = @{
        'GW'      = 0; 'GW_sec'  = 0
        'DNS'     = 0; 'DNS_sec' = 0
        'ISP'     = 0; 'ISP_sec' = 0
        'SRV'     = 0; 'SRV_sec' = 0
    }
    foreach ($ev in $script:Events) {
        $sec = if (-not $ev.Ongoing -and $ev.EndTime) { [int]($ev.EndTime - $ev.Time).TotalSeconds } else { $ev.Count }
        if     ($ev.Diag -match 'GW:FAIL')        { $segmentCounts.GW++;  $segmentCounts.GW_sec  += $sec }
        elseif ($ev.Diag -match 'DNS:FAIL')        { $segmentCounts.DNS++; $segmentCounts.DNS_sec += $sec }
        elseif ($ev.Diag -match 'Net:FAIL|ISP')    { $segmentCounts.ISP++; $segmentCounts.ISP_sec += $sec }
        elseif ($ev.Diag -match '사내')             { $segmentCounts.SRV++; $segmentCounts.SRV_sec += $sec }
    }

    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('구간 분석 요약:')
    $null = $sb.AppendLine('  게이트웨이 장애 : {0}건 (총 {1}초)' -f $segmentCounts.GW,  $segmentCounts.GW_sec)
    $null = $sb.AppendLine('  DNS 서버 장애   : {0}건 (총 {1}초)' -f $segmentCounts.DNS, $segmentCounts.DNS_sec)
    $null = $sb.AppendLine('  ISP 구간 장애   : {0}건 (총 {1}초)' -f $segmentCounts.ISP, $segmentCounts.ISP_sec)
    $null = $sb.AppendLine('  사내 서버 장애  : {0}건 (총 {1}초)' -f $segmentCounts.SRV, $segmentCounts.SRV_sec)
    $null = $sb.AppendLine('')
    $null = $sb.AppendLine('초기 Traceroute:')
    $null = $sb.AppendLine('  [참고] traceroute.txt 파일 확인')
    $null = $sb.AppendLine('=' * 60)

    $sb.ToString() | Set-Content -LiteralPath $reportFile -Encoding UTF8

    Write-Host "`n${GREEN}리포트 저장: $reportFile${NC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────
Invoke-InputCollection

Write-Host "${YELLOW}traceroute 실행 중 (잠시 기다려 주세요)...${NC}"
Initialize-LogDir
Invoke-Traceroute

$script:StartTime = Get-Date
$dnsInterval      = 10
$lastDnsTick      = -$dnsInterval

Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    New-SummaryReport
} | Out-Null

try {
    while ($true) {
        foreach ($t in $script:Targets) {
            Test-IcmpTarget $t
        }

        $elapsed = [int]((Get-Date) - $script:StartTime).TotalSeconds
        if (($elapsed - $lastDnsTick) -ge $dnsInterval) {
            $lastDnsTick = $elapsed
            Test-DnsQuery
        }

        Show-Dashboard
        Start-Sleep -Seconds 1
    }
}
finally {
    New-SummaryReport
}
