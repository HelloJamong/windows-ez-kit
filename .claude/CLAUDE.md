# Windows-EZ-Kit 프로젝트 가이드

## 프로젝트 개요

Windows Ez Kit은 Windows 서버/PC 관리자와 운영자를 위한 편리한 스크립트 도구 모음입니다. 시스템 모니터링, 네트워크 설정, 보안 점검 등 일상적인 운영 작업을 자동화하고 간소화하는 스크립트를 제공합니다.

### 프로젝트 목표

- **자동화**: 반복적인 운영 작업을 자동화하여 운영 효율성 향상
- **안정성**: 백업 및 복구 기능을 통한 안전한 시스템 변경
- **이식성**: 외부 의존성을 최소화한 순수 BAT/PS1 기반 스크립트
- **사용 편의성**: 직관적인 인터페이스와 상세한 문서 제공

### 기술 스택

- **기본 언어**: Windows Batch (`.bat`) — 단순 자동화, 메뉴, 실행 진입점
- **보조 언어**: PowerShell 5.1+ (`.ps1`) — 복잡한 로직, 객체 처리, API 연동
- **대상 OS**: Windows 10 / 11, Windows Server 2019 / 2022
- **컬러 출력**: BAT — ANSI escape (ESC trick), PS1 — `Write-Host -ForegroundColor`
- **압축**: `Compress-Archive` (PowerShell 내장)
- **타임스탬프**: PowerShell `Get-Date -Format "yyyyMMdd_HHmmss"`

## 프로젝트 구조

```
windows-ez-kit/
├── .claude/                          # Claude Code 설정 (이 파일)
├── README.md                         # 프로젝트 메인 문서
├── export.bat                        # 스크립트 ZIP 내보내기
└── scripts/                          # 모든 스크립트 모음
    ├── sort_by_name/                 # 파일 이름순 정리
    │   ├── main.bat
    │   └── README.md
    └── disk_tree/                    # 폴더 트리 분석
        ├── main.ps1
        └── README.md
```

---

## 스크립트별 상세 정보

### 1. Sort by Name (`sort_by_name/`)

**목적**: 배치 파일이 위치한 폴더의 파일을 이름순으로 정렬하여 `접두사_001` 형식으로 일괄 변경

#### 파일 구조

```
sort_by_name/
├── main.bat          # 메인 스크립트
└── README.md         # 사용 가이드
```

#### 주요 기능

- 폴더 내 파일을 이름 오름차순(알파벳/유니코드) 정렬
- 사용자 지정 접두사 + 3자리 이상 순번(`001`, `002`, ...) 형식으로 일괄 변경
- 원본 확장자 유지
- 실행 전 미리보기 및 사용자 확인
- 이름 충돌 방지 2단계 변경 (원본 → 임시명 → 최종명)
- 복원 스크립트 자동 생성 (`_sort_backup\restore_YYYYMMDD_HHMMSS.bat`)

#### 기술적 특징

- 순수 BAT 스크립트 (PowerShell은 타임스탬프 생성에만 사용)
- `dir /b /o:n /a:-d` 기반 이름순 정렬 (하위 폴더 제외)
- `setlocal EnableDelayedExpansion` 기반 동적 배열 (`FILE_1`, `FILE_2`, ...)
- 자리수 자동 결정 (파일 수 ≤ 999: 3자리, ≤ 9999: 4자리, ≤ 99999: 5자리)

#### 사용 방법

```bat
:: 정리할 폴더에 main.bat 복사 후 실행
main.bat
```

#### 지원 환경

- Windows 10 / 11
- Windows Server 2019 / 2022

---

### 2. Disk Tree (`disk_tree/`)

**목적**: 지정한 폴더의 하위 구조를 트리 형태로 시각화하고, 각 파일·폴더의 크기를 표시하는 디스크 분석 도구

#### 파일 구조

```
disk_tree/
├── main.ps1          # 단일 스크립트 (입력/탐색/렌더링/저장 전체 포함)
└── README.md         # 사용 가이드
```

#### 주요 기능

- 폴더 하위 전체를 `├──`, `└──`, `│` 문자로 트리 구조 시각화
- 파일마다 이름 + 크기(B/KB/MB/GB 자동 단위) 표시
- 폴더마다 하위 전체 합산 크기 표시
- 최대 탐색 깊이 지정 가능 (기본: 무제한)
- 콘솔 출력 + TXT 보고서 자동 저장 (`_disk_tree_report\report_YYYYMMDD_HHMMSS.txt`)
- 접근 권한 없는 폴더는 스킵 후 경고 표시

#### 기술적 특징

- 단일 PowerShell 스크립트 (PS1) — BAT 진입점 없음
- 폴더 크기 캐시로 중복 탐색 방지 (`$script:SizeCache` 해시테이블)
- `Strip-Ansi` 함수로 콘솔(컬러)·파일(순수 텍스트) 동시 출력
- `_disk_tree_report` 폴더는 크기 집계 및 트리 렌더링에서 자동 제외

#### 사용 방법

```powershell
:: PowerShell 콘솔에서 실행
.\main.ps1

:: 실행 정책 문제 시
powershell -ExecutionPolicy Bypass -File ".\main.ps1"
```

#### 지원 환경

- Windows 10 / 11
- Windows Server 2019 / 2022
- PowerShell 5.1 이상

---

## 스크립트 패턴

### BAT 기본 패턴

```bat
@echo off
setlocal EnableDelayedExpansion

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: <스크립트명> - <한 줄 설명>
::
:: 사용법: main.bat [옵션]
:: 목적:  <목적>
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: ANSI 색상 (Windows 10+)
for /f "delims=" %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "CYAN=%ESC%[36m"
set "BOLD=%ESC%[1m"
set "NC=%ESC%[0m"

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_NAME=%~nx0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"') do set "TIMESTAMP=%%t"
set "BACKUP_DIR=%SCRIPT_DIR%_backup"
set "RESTORE_FILE=%BACKUP_DIR%\restore_%TIMESTAMP%.bat"

call :main
exit /b %errorlevel%

:main
    call :check_admin     || exit /b 1
    call :backup          || exit /b 1
    call :validate        || exit /b 1
    call :execute         || exit /b 1
    call :generate_report
    exit /b 0

:check_admin
    net session >nul 2>&1
    if %errorlevel% neq 0 (
        echo %RED%관리자 권한이 필요합니다. 관리자 권한으로 실행하세요.%NC%
        exit /b 1
    )
    exit /b 0

:error_exit
    echo %RED%ERROR: %~1%NC% 1>&2
    exit /b 1
```

### PS1 보조 패턴 (BAT 한계 시 사용)

```powershell
#Requires -Version 5.1
#Requires -RunAsAdministrator
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile   = Join-Path $ScriptDir "logs\script_$Timestamp.log"

function Write-Status([string]$msg, [string]$color = "Green") {
    Write-Host $msg -ForegroundColor $color
}

function Main {
    # 1. 환경/권한 확인
    # 2. 백업
    # 3. 검증
    # 4. 실행
    # 5. 검증
    # 6. 보고서 생성
}

Main
```

---

## 백업 시스템 패턴

모든 스크립트는 타임스탬프 기반 백업 시스템 사용:

```
<스크립트 폴더>\_backup\backup_YYYYMMDD_HHMMSS\
├── backup_info.txt        # 백업 정보 및 복구 방법
├── restore.bat            # 자동 생성된 복구 스크립트
└── <백업 파일/폴더>
```

---

## 개발 가이드

### 코드 작성 원칙

1. **BAT 우선**: 단순 작업은 `.bat`으로, 복잡한 로직만 `.ps1` 사용
2. **백업 필수**: 시스템 변경 전 항상 자동 백업 구현
3. **에러 처리**: 명시적 에러 처리 및 복구 로직 구현 (`exit /b 1` 활용)
4. **타임스탬프**: 백업/로그 파일은 `yyyyMMdd_HHmmss` 형식 사용
5. **사용자 확인**: 위험한 작업 전 사용자 확인 프롬프트 (`set /p CONFIRM=`)
6. **컬러 출력**: ANSI escape 코드로 가독성 높은 출력
7. **상세 로깅**: 실행 과정과 결과를 파일로 저장

### 새로운 스크립트 추가 시

1. `scripts\<script-name>\` 폴더 생성
2. `README.md` 작성 (기존 스크립트와 동일한 형식)
3. `main.bat` 작성 (위 패턴 참고, 필요 시 `.ps1` 추가)
4. 루트 `README.md`의 "스크립트 카탈로그" 섹션에 추가
5. 이 `CLAUDE.md`의 "스크립트별 상세 정보" 섹션에 추가

### 테스트 가이드

1. **개발 환경**: 먼저 테스트 VM(Windows 10/11 클린 환경)에서 검증
2. **권한 시나리오**: 관리자 권한 유/무 양쪽 모두 테스트
3. **백업 검증**: 백업이 정상적으로 생성되는지 확인
4. **복구 테스트**: `restore.bat` 스크립트가 정상 동작하는지 확인
5. **에러 시나리오**: 실패 상황에서 롤백이 정상 동작하는지 확인

### 문서화 규칙

각 스크립트 폴더에는 반드시 다음을 포함:

1. **README.md**: 사용 가이드 (목적, 기능, 사용법, 문제 해결)
2. **스크립트 주석**: 함수/라벨별 목적과 파라미터 설명
3. **사용 예시**: 실제 사용 예시 및 출력 예시

---

## 보안 및 주의사항

### 관리자 권한
대부분의 스크립트는 시스템 변경을 위해 관리자 권한 필요. 스크립트 최상단에서 권한 확인 필수.

### PowerShell 실행 정책
PS1 스크립트 실행 시 `Set-ExecutionPolicy` 변경이 필요할 수 있음. 스크립트 README에 안내 포함.

### 백업 확인
시스템 변경 전 항상 백업이 정상적으로 생성되었는지 확인.

### 테스트 환경 우선
프로덕션 환경에 적용하기 전 반드시 테스트 환경에서 검증.

---

## 버전 관리

- Git을 활용한 버전 관리
- 커밋 메시지는 명확하게 (`feat:`, `fix:`, `docs:` 등)
- 중요한 변경은 태그 생성

---

## 라이선스

MIT License
