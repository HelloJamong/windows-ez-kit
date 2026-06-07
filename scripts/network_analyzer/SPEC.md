# Spec: Network Analyzer

## Objective

Windows 환경에서 네트워크 연결 문제 발생 시 **어느 구간**에서 **어느 시점**에 장애가 발생했는지 분석하는 도구.

운영자가 네트워크 장애 발생 즉시 실행하여:
1. 각 구간(게이트웨이, DNS, 인터넷, 사내 서버)의 상태를 실시간 대시보드로 모니터링
2. 장애 구간을 자동 진단 (게이트웨이 문제 / DNS 문제 / ISP 문제 / 사내 서버 문제 구분)
3. 종료 시 통합 타임라인 로그 + 요약 리포트 자동 생성

**대상 사용자**: Windows 서버/PC 운영자  
**대상 OS**: Windows 10/11, Windows Server 2019/2022

---

## Tech Stack

| 구분 | 기술 | 역할 |
|------|------|------|
| 주 스크립트 | PowerShell 5.1+ | 전체 로직 (입력 수집, traceroute, 모니터링, 대시보드, 로그, 리포트) |
| 진입점 | Windows Batch (.bat) | 더블클릭 실행 지원, ExecutionPolicy Bypass 처리 |
| 외부 의존성 | 없음 | `Test-Connection`, `Resolve-DnsName`, `tracert` 내장 명령어만 사용 |

---

## Commands

```
# PS1 직접 실행
powershell -ExecutionPolicy Bypass -File ".\main.ps1"

# BAT 더블클릭 실행
main.bat
```

---

## Project Structure

```
scripts/network_analyzer/
├── main.bat                         # 더블클릭 진입점 — main.ps1 실행
├── main.ps1                         # 전체 로직
├── SPEC.md                          # 이 스펙 문서
└── README.md                        # 사용 가이드

# 실행 시 자동 생성되는 로그 폴더
scripts/network_analyzer/_network_analyzer_logs/
└── YYYYMMDD_HHMMSS/
    ├── timeline.txt                 # 통합 타임라인 로그 (실시간 append)
    ├── traceroute.txt               # 초기 traceroute 결과
    └── report.txt                   # 종료 시 요약 리포트
```

---

## 입력 수집 흐름

```
[1] Gateway IP         (필수, 예: 192.168.1.1)
[2] DNS IP             (필수, 예: 8.8.8.1)
[3] DNS 쿼리 테스트 도메인  (기본: google.com, Enter로 기본값 사용)
[4] 추가 대상 #1 — 레이블 + IP  (예: "Internet 8.8.8.8", Enter로 스킵)
[5] 추가 대상 #2 — 레이블 + IP  (예: "InternalSrv 10.0.0.100", Enter로 스킵)
```

입력 검증:
- IP 형식: `^\d{1,3}(\.\d{1,3}){3}$` 패턴 + 각 옥텟 0~255 범위
- 빈 필수값: 재입력 프롬프트
- 레이블 + IP 형식 오류: 재입력 프롬프트

---

## 모니터링 루프

```
시작 시 1회:
  └─ 모든 대상에 tracert 실행 → traceroute.txt 저장 (백그라운드)

매 1초:
  ├─ ICMP ping — 모든 대상 (Test-Connection -Count 1)
  ├─ 상태 누적 (sent / received / totalMs / consecFail 갱신)
  ├─ timeline.txt append
  └─ 대시보드 Clear + 재렌더링

매 10초:
  └─ DNS 쿼리 테스트 (Resolve-DnsName 도메인 -Server DNS_IP)
     └─ timeline.txt append
```

---

## 대시보드 레이아웃

```
╔══════════════════════════════════════════════════════════════════════╗
║  Network Connectivity Analyzer                                      ║
║  Started: 2026-06-05 10:30:00        Elapsed: 00:05:23             ║
╠══════════════════════════════════════════════════════════════════════╣
║  TARGET         IP              STATUS    LATENCY  LOSS%   SENT    ║
║  Gateway        192.168.1.1     ● OK       12ms    0.0%    323     ║
║  DNS            8.8.8.1         ● OK        8ms    0.0%    323     ║
║  Internet       8.8.8.8         ✗ FAIL      ---   15.3%    323     ║
║  InternalSrv    10.0.0.100      ● OK       45ms    2.1%    323     ║
╠══════════════════════════════════════════════════════════════════════╣
║  DNS Query  google.com via 8.8.8.1     ● OK  45ms  (33회 테스트)  ║
╠══════════════════════════════════════════════════════════════════════╣
║  SEGMENT DIAGNOSIS                                                  ║
║  GW:OK  DNS:OK  Internet:FAIL  → ISP / 업스트림 구간 문제          ║
╠══════════════════════════════════════════════════════════════════════╣
║  RECENT EVENTS (최근 5건)                                           ║
║  [10:35:01] Internet (8.8.8.8) FAIL 연속 14회                      ║
║  [10:34:48] Internet (8.8.8.8) 장애 시작                           ║
║  [10:34:21] InternalSrv (10.0.0.100) FAIL → 3초 후 복구            ║
║                                                                     ║
║                                                                     ║
╚══════════════════════════════════════════════════════════════════════╝
  Ctrl+C 또는 창 닫기 → 모니터링 종료 후 리포트 자동 생성
```

색상 규칙:
- `● OK` — GREEN
- `✗ FAIL` — RED
- 연속 실패 이벤트 — YELLOW
- 헤더 / 구분선 — CYAN
- 진단 메시지 — YELLOW (정상 시 GRAY)

---

## 구간 진단 로직

| GW   | DNS  | Internet | Custom | 진단                           |
|------|------|----------|--------|-------------------------------|
| FAIL | any  | any      | any    | 로컬 네트워크 / 게이트웨이 문제  |
| OK   | FAIL | FAIL     | any    | DNS 서버 문제                  |
| OK   | OK   | FAIL     | OK/—   | ISP / 업스트림 라우팅 문제      |
| OK   | OK   | OK       | FAIL   | 사내 서버 문제                  |
| OK   | OK   | FAIL     | FAIL   | 업스트림 / 라우팅 문제          |
| OK   | OK   | OK       | OK/—   | 정상                           |

Custom 대상이 입력되지 않은 경우 해당 컬럼 무시.  
연속 실패 3회 이상 시 `[EVENT]` 로그 기록.

---

## 로그 포맷 (timeline.txt)

```
[10:30:00.123] [TRACE] [Gateway     ] traceroute 시작 → 192.168.1.1
[10:30:01.234] [TRACE] [Gateway     ] hop 1: 192.168.1.1  1ms
[10:30:05.000] [PING ] [Gateway     ] OK    12ms TTL=64
[10:30:05.001] [PING ] [DNS         ] OK     8ms TTL=64
[10:30:05.002] [PING ] [Internet    ] FAIL  timeout
[10:30:05.003] [PING ] [InternalSrv ] OK    45ms TTL=128
[10:30:10.004] [DNS  ] [google.com  ] OK    45ms via 8.8.8.1
[10:30:15.002] [PING ] [Internet    ] FAIL  timeout
[10:30:15.005] [EVENT] [Internet    ] FAIL 연속 3회 | GW:OK DNS:OK → ISP 구간 문제 의심
```

---

## 요약 리포트 (report.txt)

```
============================================================
  Network Connectivity Analysis Report
============================================================
  기간  : 2026-06-05 10:30:00 ~ 10:35:23
  소요  : 5분 23초
  샘플  : 323회

TARGET 통계:
  Gateway       192.168.1.1   323/323 (100.0%)  avg=11ms  min=8ms   max=45ms
  DNS           8.8.8.1       323/323 (100.0%)  avg=8ms   min=6ms   max=22ms
  Internet      8.8.8.8       273/323 ( 84.6%)  avg=14ms  min=9ms   max=120ms
  InternalSrv   10.0.0.100    316/323 ( 97.8%)  avg=45ms  min=40ms  max=89ms

DNS 쿼리 (google.com via 8.8.8.1):
  성공: 32/33 (97.0%)  avg=45ms

장애 이벤트:
  10:34:48 ~ 10:35:02  Internet (8.8.8.8)      연속 14회 실패  [진단: ISP 구간]
  10:34:21 ~ 10:34:24  InternalSrv (10.0.0.100) 연속 3회 실패  [진단: 사내 서버]

구간 분석 요약:
  게이트웨이 장애 : 0건
  DNS 서버 장애   : 0건
  ISP 구간 장애   : 1건 (총 14초)
  사내 서버 장애  : 1건 (총 3초)

초기 Traceroute:
  [참고] traceroute.txt 파일 확인
============================================================
```

---

## Code Style

기존 프로젝트 패턴을 따름:

```powershell
#Requires -Version 5.1
<#
.SYNOPSIS
    Network Analyzer — 네트워크 구간별 연결 상태 모니터링 및 장애 분석
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
$GRAY   = "$ESC[90m"
$BOLD   = "$ESC[1m"
$NC     = "$ESC[0m"

# ── Target 데이터 구조 ─────────────────────────────────────────────────────────
# @{
#   Name       = 'Gateway'
#   Role       = 'GW'          # GW | DNS | Custom1 | Custom2
#   IP         = '192.168.1.1'
#   Sent       = 0
#   Received   = 0
#   TotalMs    = 0
#   ConsecFail = 0
#   LastStatus = ''            # 'OK' | 'FAIL'
#   LastMs     = 0
# }
```

네이밍:
- 함수: `Verb-Noun` PascalCase (`Test-IcmpTarget`, `Show-Dashboard`, `Write-TimelineLog`)
- 지역 변수: `$camelCase`
- 스크립트 전역: `$script:PascalCase`
- ANSI 상수: `$UPPER_CASE`
- 섹션 구분: `# ── Section ──────────...` (68자 고정)

---

## Testing Strategy

자동화 프레임워크 없음. 수동 검증 시나리오:

| # | 시나리오 | 검증 방법 |
|---|---------|---------|
| 1 | 정상 실행 | 유효 IP 입력 → 대시보드 렌더링, 3개 파일 생성 확인 |
| 2 | 입력 오류 | 잘못된 IP 형식 입력 → 재입력 프롬프트 출력 확인 |
| 3 | FAIL 감지 | 존재하지 않는 IP 입력 → ✗ FAIL 표시, 구간 진단 메시지 확인 |
| 4 | Ctrl+C 종료 | Ctrl+C 후 report.txt 자동 생성 확인 |
| 5 | 창 닫기 종료 | 창 X 버튼 → report.txt 자동 생성 확인 |
| 6 | 추가 대상 스킵 | Enter 스킵 → 2개 타겟만 대시보드 표시 확인 |
| 7 | 추가 대상 입력 | 레이블 + IP 입력 → 4개 타겟 모두 표시 확인 |
| 8 | DNS 쿼리 | 10초 경과 후 [DNS] 로그 라인 확인 |

---

## Boundaries

- **Always**: IP 형식 유효성 검사, `try/finally`로 리포트 생성 보장, 모든 파일 UTF-8 인코딩
- **Ask first**: ping 간격 변경 (현재 1초 고정), DNS 쿼리 간격 변경 (현재 10초 고정), traceroute 타임아웃 조정
- **Never**: 관리자 권한 요구, 외부 모듈/패키지 의존, 실행 정책 영구 변경 (`Set-ExecutionPolicy` 미사용)

---

## Success Criteria

- [ ] Gateway + DNS 필수 입력, 추가 대상 최대 2개 옵션 입력 (Enter 스킵 지원)
- [ ] 시작 시 모든 대상에 traceroute 1회 실행, `traceroute.txt` 저장
- [ ] 매 1초 ICMP ping, 매 10초 DNS 쿼리 테스트 실행
- [ ] 콘솔 대시보드: 실시간 갱신 (상태, 지연, 손실률, 최근 이벤트 5건, 구간 진단)
- [ ] `timeline.txt`: `[PING]`/`[DNS]`/`[TRACE]`/`[EVENT]` prefix 포함 단일 타임라인
- [ ] Ctrl+C 또는 창 닫기 시 `report.txt` 자동 생성
- [ ] `report.txt`: 대상별 통계, 장애 이벤트 목록, 구간 분석 요약, traceroute 참조 포함
- [ ] 로그 저장: `_network_analyzer_logs\YYYYMMDD_HHMMSS\` 하위 3개 파일
- [ ] PS1 직접 실행 및 BAT 더블클릭 실행 모두 지원
- [ ] 일반 사용자 권한으로 실행 가능 (관리자 권한 불필요)

---

## Open Questions

없음. 모든 요구사항 확정.
