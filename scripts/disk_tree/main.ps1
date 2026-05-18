#Requires -Version 5.1
<#
.SYNOPSIS
    Disk Tree Analyzer — 폴더 트리 구조 및 파일 크기 분석
.NOTES
    실행: powershell -ExecutionPolicy Bypass -File ".\main.ps1"
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── ANSI colors ───────────────────────────────────────────────────────────────
$ESC    = [char]27
$CYAN   = "$ESC[36m"
$GREEN  = "$ESC[32m"
$YELLOW = "$ESC[33m"
$RED    = "$ESC[31m"
$BOLD   = "$ESC[1m"
$NC     = "$ESC[0m"
$SEP    = '─' * 60

# ── Globals ───────────────────────────────────────────────────────────────────
$script:TotalFiles   = 0
$script:TotalFolders = 0
$script:SizeCache    = @{}

# ── Helpers ───────────────────────────────────────────────────────────────────
function Format-Size([long]$Bytes) {
    if ($Bytes -ge 1GB) { return '{0:N1} GB' -f ($Bytes / 1GB) }
    if ($Bytes -ge 1MB) { return '{0:N1} MB' -f ($Bytes / 1MB) }
    if ($Bytes -ge 1KB) { return '{0:N1} KB' -f ($Bytes / 1KB) }
    return "$Bytes B"
}

function Strip-Ansi([string]$Text) {
    return $Text -replace '\x1b\[[0-9;]*m', ''
}

function Out-Both([string]$ConsoleText, [System.IO.StreamWriter]$Writer) {
    Write-Host $ConsoleText
    $Writer.WriteLine((Strip-Ansi $ConsoleText))
}

# 폴더 크기 합산 (결과 캐시로 중복 탐색 방지)
function Get-FolderSize([string]$Path) {
    if ($script:SizeCache.ContainsKey($Path)) { return [long]$script:SizeCache[$Path] }
    [long]$size = 0
    try {
        foreach ($item in (Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop)) {
            $size += if ($item.PSIsContainer) { Get-FolderSize $item.FullName } else { $item.Length }
        }
    } catch { }
    $script:SizeCache[$Path] = $size
    return $size
}

# 트리 재귀 렌더링
function Write-Tree {
    param(
        [string]$Path,
        [string]$Prefix,
        [int]$CurrentDepth,
        [int]$MaxDepth,
        [System.IO.StreamWriter]$Writer,
        [string]$SkipName = ''
    )

    try {
        $raw = Get-ChildItem -LiteralPath $Path -Force -ErrorAction Stop
    } catch {
        Out-Both "${YELLOW}⚠ 액세스 거부: $Path${NC}" $Writer
        return
    }

    $folders = @($raw | Where-Object { $_.PSIsContainer -and ($SkipName -eq '' -or $_.Name -ne $SkipName) } | Sort-Object Name)
    $files   = @($raw | Where-Object { -not $_.PSIsContainer } | Sort-Object Name)
    $items   = $folders + $files

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item   = $items[$i]
        $isLast = $i -eq ($items.Count - 1)
        $con    = if ($isLast) { '└── ' } else { '├── ' }
        $ext    = if ($isLast) { '    ' } else { '│   ' }

        if ($item.PSIsContainer) {
            $script:TotalFolders++
            $sizeStr = Format-Size (Get-FolderSize $item.FullName)
            $plain   = "${Prefix}${con}$($item.Name)\"
            $pad     = ' ' * [Math]::Max(1, 56 - $plain.Length)
            Out-Both "${Prefix}${con}${CYAN}$($item.Name)\${NC}${pad}${GREEN}[$sizeStr]${NC}" $Writer

            if ($MaxDepth -le 0 -or $CurrentDepth -lt $MaxDepth) {
                Write-Tree -Path $item.FullName -Prefix "${Prefix}${ext}" `
                    -CurrentDepth ($CurrentDepth + 1) -MaxDepth $MaxDepth -Writer $Writer
            }
        } else {
            $script:TotalFiles++
            $sizeStr = Format-Size $item.Length
            $plain   = "${Prefix}${con}$($item.Name)"
            $pad     = ' ' * [Math]::Max(1, 56 - $plain.Length)
            Out-Both "${Prefix}${con}$($item.Name)${pad}$($sizeStr.PadLeft(12))" $Writer
        }
    }
}

# ── Main ──────────────────────────────────────────────────────────────────────
Write-Host "`n${BOLD}${CYAN}Disk Tree Analyzer${NC}`n"

# 1. 경로 입력
$targetPath = ''
while ($true) {
    $targetPath = (Read-Host '분석할 폴더 경로를 입력하세요').Trim().Trim('"')
    if (Test-Path -LiteralPath $targetPath -PathType Container) { break }
    Write-Host "${RED}경로를 찾을 수 없습니다. 다시 입력해주세요.${NC}"
}

# 2. 최대 깊이 입력
$maxDepthStr = Read-Host '최대 깊이 입력 (Enter = 무제한)'
$maxDepth    = if ($maxDepthStr -match '^\d+$' -and [int]$maxDepthStr -gt 0) { [int]$maxDepthStr } else { 0 }

# 3. 보고서 파일 준비
$timestamp  = Get-Date -Format 'yyyyMMdd_HHmmss'
$reportDir  = Join-Path $targetPath '_disk_tree_report'
$null       = New-Item -ItemType Directory -Path $reportDir -Force
$reportFile = Join-Path $reportDir "report_$timestamp.txt"
$writer     = [System.IO.StreamWriter]::new($reportFile, $false, [System.Text.Encoding]::UTF8)

try {
    # 4. 헤더 출력
    $depthLabel = if ($maxDepth -gt 0) { "$maxDepth" } else { '무제한' }
    Write-Host ''
    foreach ($line in @(
        "분석 경로  : $targetPath",
        "최대 깊이  : $depthLabel",
        "분석 시각  : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')",
        $SEP
    )) { Out-Both $line $writer }

    # 5. 루트 크기 (_disk_tree_report 제외)
    [long]$rootSize = 0
    foreach ($item in (Get-ChildItem -LiteralPath $targetPath -Force)) {
        if ($item.Name -eq '_disk_tree_report') { continue }
        $rootSize += if ($item.PSIsContainer) { Get-FolderSize $item.FullName } else { $item.Length }
    }
    $rootName    = Split-Path $targetPath -Leaf
    $rootSizeStr = Format-Size $rootSize

    Write-Host "${CYAN}${rootName}\${NC} ${GREEN}[$rootSizeStr]${NC}"
    $writer.WriteLine("${rootName}\ [$rootSizeStr]")

    # 6. 트리 출력
    Write-Tree -Path $targetPath -Prefix '' -CurrentDepth 1 -MaxDepth $maxDepth `
        -Writer $writer -SkipName '_disk_tree_report'

    # 7. 요약
    Out-Both $SEP $writer
    Out-Both "${BOLD}총 폴더: $($script:TotalFolders)개   총 파일: $($script:TotalFiles)개   총 크기: $rootSizeStr${NC}" $writer
    Out-Both "${GREEN}보고서 저장: $reportFile${NC}" $writer

} finally {
    $writer.Flush()
    $writer.Close()
}

Write-Host ''
