#Requires -Version 5.1
<#
.SYNOPSIS
    Netstat Status Monitor — 지정 포트의 ESTABLISHED 상태를 1초 단위로 기록
.NOTES
    실행: powershell -ExecutionPolicy Bypass -File ".\main.ps1"
    로그: C:\Temp\yyyyMMdd_HHmmss_<port>_status.txt
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Console colors ────────────────────────────────────────────────────────────
$ESC    = [char]27
$CYAN   = "$ESC[36m"
$GREEN  = "$ESC[32m"
$YELLOW = "$ESC[33m"
$RED    = "$ESC[31m"
$BOLD   = "$ESC[1m"
$NC     = "$ESC[0m"

# ── Sleep prevention ──────────────────────────────────────────────────────────
if (-not ('WindowsEzKit.PowerState' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WindowsEzKit {
    public static class PowerState {
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern uint SetThreadExecutionState(uint esFlags);
    }
}
'@
}

$ES_CONTINUOUS      = [uint32]2147483648
$ES_SYSTEM_REQUIRED = [uint32]1

function Enable-SleepPrevention {
    $flags = $ES_CONTINUOUS -bor $ES_SYSTEM_REQUIRED
    [void][WindowsEzKit.PowerState]::SetThreadExecutionState($flags)
}

function Disable-SleepPrevention {
    [void][WindowsEzKit.PowerState]::SetThreadExecutionState($ES_CONTINUOUS)
}

# ── Helpers ───────────────────────────────────────────────────────────────────
function Read-Port {
    while ($true) {
        $value = (Read-Host '스캔할 포트 번호를 입력하세요').Trim()

        if ($value -match '^\d+$') {
            $portNumber = [int]$value
            if ($portNumber -ge 1 -and $portNumber -le 65535) {
                return $value
            }
        }

        Write-Host "${RED}1~65535 사이의 포트 번호를 입력하세요.${NC}"
    }
}

function Get-NetstatRows {
    param([string]$Port)

    # Requirement-compatible command shape:
    # netstat -an | findstr "포트"
    $command = 'netstat -an | findstr /C:"{0}"' -f $Port
    $rows = & cmd.exe /d /c $command 2>$null

    if ($null -eq $rows) {
        return @()
    }

    return @($rows | Where-Object { $_ -and $_.Trim().Length -gt 0 })
}

function Write-LogLine {
    param(
        [string]$Path,
        [string]$Text
    )

    Add-Content -LiteralPath $Path -Value $Text -Encoding UTF8
    Write-Host $Text
}

# ── Main ──────────────────────────────────────────────────────────────────────
Write-Host "`n${BOLD}${CYAN}Netstat Status Monitor${NC}`n"

$port = Read-Port
$startTime = Get-Date
$timestamp = $startTime.ToString('yyyyMMdd_HHmmss')
$logRoot = 'C:\Temp'
$logFile = Join-Path $logRoot ("{0}_{1}_status.txt" -f $timestamp, $port)

if (-not (Test-Path -LiteralPath $logRoot -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $logRoot -Force
}

@(
    ('Start Time: {0}' -f $startTime.ToString('yyyy-MM-dd HH:mm:ss')),
    ('Port: {0}' -f $port),
    ('Command: netstat -an | findstr "{0}"' -f $port),
    ('Log File: {0}' -f $logFile),
    'Interval: 1 second',
    'Sleep Prevention: enabled while this script is running',
    '----------------------------------------------------------------------'
) | Set-Content -LiteralPath $logFile -Encoding UTF8

Write-Host "${GREEN}로그 파일: $logFile${NC}"
Write-Host "${YELLOW}중지하려면 창을 닫거나 Ctrl+C를 누르세요.${NC}`n"

Enable-SleepPrevention

try {
    while ($true) {
        $now = Get-Date
        $timeLabel = $now.ToString('HH:mm:ss')
        $rows = @(Get-NetstatRows -Port $port)
        $hasEstablished = @($rows | Where-Object { $_ -match '\bESTABLISHED\b' }).Count -gt 0

        if ($rows.Count -eq 0) {
            Write-LogLine -Path $logFile -Text ("{0} - [NOT_ESTABLISHED] no netstat rows for port {1}" -f $timeLabel, $port)
        } else {
            foreach ($row in $rows) {
                Write-LogLine -Path $logFile -Text ("{0} - {1}" -f $timeLabel, $row.Trim())
            }

            if (-not $hasEstablished) {
                Write-LogLine -Path $logFile -Text ("{0} - [NOT_ESTABLISHED] no ESTABLISHED rows for port {1}" -f $timeLabel, $port)
            }
        }

        Start-Sleep -Seconds 1
    }
} finally {
    Disable-SleepPrevention
    Write-Host "`n${YELLOW}모니터링을 종료했습니다. 로그 파일: $logFile${NC}"
}
