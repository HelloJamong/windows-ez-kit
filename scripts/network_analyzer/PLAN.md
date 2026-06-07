# Implementation Plan: Network Analyzer

## Overview

`main.ps1` 단일 파일에 전체 로직을 구현하고 `main.bat`으로 진입점을 제공한다.
총 9개 태스크를 3개 체크포인트로 나눠 단계적으로 검증하며 진행한다.

---

## Architecture Decisions

| 결정 | 근거 |
|------|------|
| `main.ps1` 단일 파일 구조 | `disk_tree`, `netstat_status_monitor`와 동일한 패턴; BAT는 진입점만 담당 |
| `Test-Connection -Count 1` (PS5 내장) | 외부 의존성 없이 ICMP ping 구현 가능 |
| `tracert -d` 사용 | `-d` 플래그로 DNS 역조회 생략 → 속도 개선 + 로케일 무관한 출력 |
| `try/finally` + `Register-EngineEvent` 조합 | PS5.1에서 Ctrl+C는 `finally`가 신뢰할 수 있으나, 창 X버튼 종료 시 `finally` 미보장 → `PowerShell.Exiting` 이벤트로 보완 |
| 보고서 이중 실행 방지 플래그 (`$script:ReportWritten`) | Ctrl+C + Exiting 이벤트 동시 발생 시 report.txt 중복 생성 방지 |
| tracert 출력 raw 저장 | 로케일별 헤더 텍스트를 파싱하지 않고 raw 저장, hop IP만 타임라인에 기록 |

---

## Dependency Graph

```
[스크립트 헤더 + ANSI 상수]
    │
[입력 수집 + IP 검증]
    │
[로그 폴더 생성]  →  $script:LogDir, $script:TimelineFile
    │
[Write-TimelineLog]          ← 모든 probe 함수가 사용
    │
    ├── [Test-IcmpTarget]    ← ping 1회, 결과 반환 + timeline append
    ├── [Test-DnsQuery]      ← DNS 쿼리 1회, 결과 반환 + timeline append
    └── [Invoke-Traceroute]  ← tracert 실행, traceroute.txt 저장, [TRACE] timeline append
    │
[Get-SegmentDiagnosis]       ← 순수 함수, $Targets 배열 읽기만
    │
[모니터링 루프]               ← 1초 ping, 10초 DNS, 통계 누적, Show-Dashboard 호출
    │
[Show-Dashboard]             ← $script:Targets + $script:Events 읽기
    │
[New-SummaryReport]          ← 누적 통계 전체 사용
    │
[종료 핸들러]                 ← finally + Register-EngineEvent PowerShell.Exiting
    │
[main.bat]                   ← main.ps1 완성 후 진입점 작성
```

---

## Task List

### Phase 1: 스캐폴딩

---

#### Task 1: 스크립트 헤더 + 입력 수집 + 로그 폴더 설정

**Description:**  
`main.ps1` 뼈대를 생성한다. ANSI 상수, target 데이터 구조 정의, 사용자 입력 수집(Gateway IP 필수, DNS IP 필수, DNS 쿼리 도메인, 추가 대상 2개 옵션), IP 유효성 검사, 로그 폴더(`_network_analyzer_logs/YYYYMMDD_HHMMSS/`) 생성까지 구현한다.

**Acceptance criteria:**
- [ ] Gateway / DNS IP 빈값 입력 시 재입력 프롬프트 출력
- [ ] 잘못된 IP 형식(`999.999.0.0`, `abc`, 등) 입력 시 재입력 프롬프트 출력
- [ ] 추가 대상 Enter 스킵 시 `$script:Targets`에 포함되지 않음
- [ ] 추가 대상 `"Internet 8.8.8.8"` 형식 입력 시 레이블 + IP 분리 저장
- [ ] `_network_analyzer_logs/YYYYMMDD_HHMMSS/` 폴더 + `timeline.txt` 빈 파일 생성

**Verification:**
- [ ] 스크립트 실행 후 유효 IP 입력 → 폴더 및 파일 생성 확인
- [ ] 잘못된 IP 입력 → 재입력 요구 메시지 출력 확인

**Dependencies:** None

**Files:**
- `scripts/network_analyzer/main.ps1` (신규)

**Scope:** M

---

### Phase 2: 프로브 함수

---

#### Task 2: `Write-TimelineLog` + `Test-IcmpTarget`

**Description:**  
타임라인 로그 append 헬퍼(`Write-TimelineLog`)와 ICMP ping 프로브 함수(`Test-IcmpTarget`)를 구현한다. ping 결과(OK/FAIL, latency, TTL)를 target 해시테이블에 반영하고 `[PING]` 포맷으로 timeline.txt에 기록한다.

**Acceptance criteria:**
- [ ] `[HH:mm:ss.fff] [PING ] [TargetName  ] OK   12ms TTL=64` 형식으로 로그 기록
- [ ] `[HH:mm:ss.fff] [PING ] [TargetName  ] FAIL timeout` 형식으로 실패 로그 기록
- [ ] target 해시테이블의 `Sent`, `Received`, `TotalMs`, `ConsecFail`, `LastStatus`, `LastMs` 갱신
- [ ] PS5.1 `Test-Connection` 객체에서 `ResponseTime`, `TimeToLive` 추출 정상 동작

**Verification:**
- [ ] 유효한 IP(예: 8.8.8.8) 대상으로 함수 호출 → timeline.txt에 `[PING]` 라인 생성 확인
- [ ] 존재하지 않는 IP(예: 10.255.255.254) 대상 → `[PING] FAIL` 라인 생성 확인

**Dependencies:** Task 1

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** S

---

#### Task 3: `Test-DnsQuery`

**Description:**  
DNS 쿼리 테스트 함수(`Test-DnsQuery`)를 구현한다. `Resolve-DnsName -Name $domain -Server $dnsIp`로 실제 도메인 조회를 시도하고 결과를 `[DNS]` 포맷으로 타임라인에 기록한다. 결과는 `$script:DnsQuery` 해시테이블에 저장한다.

**Acceptance criteria:**
- [ ] `[HH:mm:ss.fff] [DNS  ] [google.com  ] OK   45ms via 8.8.8.1` 형식으로 로그 기록
- [ ] DNS 실패 시 `[DNS  ] [...] FAIL <오류 메시지>` 형식으로 기록
- [ ] `$script:DnsQuery` 해시테이블에 `LastStatus`, `LastMs`, `Sent`, `Received` 누적

**Verification:**
- [ ] 유효한 DNS IP + 도메인 입력 → `[DNS]` 성공 라인 생성 확인
- [ ] 잘못된 DNS IP 입력 → `[DNS] FAIL` 라인 생성 확인

**Dependencies:** Task 1

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** S

---

#### Task 4: `Invoke-Traceroute`

**Description:**  
각 대상에 대해 `tracert -d -w 3000 <ip>`를 실행하고 raw 출력을 `traceroute.txt`에 저장한다. hop IP만 파싱하여 `[TRACE]` 포맷으로 타임라인에도 기록한다. tracert는 시간이 걸리므로 모니터링 시작 전 별도로 실행한다.

**Acceptance criteria:**
- [ ] `traceroute.txt` 파일에 모든 대상의 tracert raw 출력 저장
- [ ] `[TRACE] [TargetName] hop N: <IP>` 형식으로 timeline.txt 기록
- [ ] tracert 실패(타임아웃, 권한 없음 등) 시 `[TRACE] [TargetName] traceroute failed` 기록
- [ ] `tracert -d` 사용으로 DNS 역조회 없이 실행 (속도 개선)

**Verification:**
- [ ] 실행 후 `traceroute.txt` 파일 내용 확인 (raw tracert 출력 포함)
- [ ] timeline.txt에 `[TRACE]` 라인 생성 확인

**Dependencies:** Task 1, Task 2 (Write-TimelineLog)

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** S

---

### Checkpoint 1: 프로브 함수 검증

- [ ] `Test-IcmpTarget` — 유효/무효 IP 양쪽 동작 확인
- [ ] `Test-DnsQuery` — 성공/실패 동작 확인
- [ ] `Invoke-Traceroute` — traceroute.txt 생성, timeline.txt에 `[TRACE]` 기록 확인
- [ ] 인간 검토 후 Phase 3 진행

---

### Phase 3: 모니터링 코어

---

#### Task 5: `Get-SegmentDiagnosis` + 모니터링 루프

**Description:**  
구간 진단 로직(`Get-SegmentDiagnosis`)과 메인 모니터링 루프를 구현한다. 루프는 매 1초 모든 대상에 ICMP ping, 매 10초 DNS 쿼리를 실행하고 통계를 누적한다. 연속 실패 3회 이상 시 `[EVENT]` 로그를 기록하고 `$script:Events` 목록에 추가한다.

**Acceptance criteria:**
- [ ] 1초 주기로 모든 대상 ping 실행 + timeline.txt에 `[PING]` 라인 append
- [ ] 10초 주기로 DNS 쿼리 실행 + timeline.txt에 `[DNS]` 라인 append
- [ ] 연속 실패 3회 시 `[EVENT]` 라인 기록 + `$script:Events` 추가 (최대 100건 유지)
- [ ] 진단 테이블 기준으로 `Get-SegmentDiagnosis` 올바른 메시지 반환

구간 진단 매핑:
```
GW:FAIL                       → "로컬 네트워크 / 게이트웨이 문제"
GW:OK  DNS:FAIL               → "DNS 서버 문제"
GW:OK  DNS:OK  Net:FAIL       → "ISP / 업스트림 라우팅 문제"
GW:OK  DNS:OK  Net:OK  C:FAIL → "사내 서버 문제"
모두 OK                        → "정상"
```

**Verification:**
- [ ] 30초 실행 후 timeline.txt에 약 30개 `[PING]` + 3개 `[DNS]` 라인 확인
- [ ] 존재하지 않는 IP를 한 대상으로 입력 → 3회 후 `[EVENT]` 라인 + 진단 메시지 확인

**Dependencies:** Task 2, Task 3, Task 4

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** M

---

### Phase 4: 대시보드

---

#### Task 6: `Show-Dashboard`

**Description:**  
콘솔 대시보드 렌더링 함수(`Show-Dashboard`)를 구현하고 모니터링 루프에서 매 1초 호출한다. `[Console]::Clear()` 후 전체 대시보드를 재렌더링한다. 대상 테이블, DNS 쿼리 행, 구간 진단, 최근 이벤트 5건을 표시한다.

**Acceptance criteria:**
- [ ] 헤더: 시작 시간 + 경과 시간 표시
- [ ] 대상 테이블: Name(12자), IP(15자), STATUS(● OK/✗ FAIL), LATENCY(---/Nms), LOSS%(소수점 1자리), SENT 컬럼 정렬
- [ ] DNS 쿼리 행: 도메인, DNS IP, 상태, 지연, 테스트 횟수
- [ ] 구간 진단 행: `Get-SegmentDiagnosis` 결과 (정상=GRAY, 장애=YELLOW)
- [ ] 최근 이벤트 5건 (5건 미만 시 빈 행으로 채워 높이 고정)
- [ ] 색상: OK=GREEN, FAIL=RED, 이벤트=YELLOW, 구분선=CYAN

**Verification:**
- [ ] 실행 후 대시보드가 매 1초 갱신되는 것 육안 확인
- [ ] 존재하지 않는 IP 대상 → `✗ FAIL` 빨간색 표시 확인
- [ ] 추가 대상 없을 때 2행, 있을 때 3~4행 표시 확인

**Dependencies:** Task 5

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** M

---

### Checkpoint 2: 실시간 모니터링 검증

- [ ] 대시보드 매 1초 갱신 확인
- [ ] 유효 IP + 무효 IP 혼합 입력 → FAIL 표시 + 구간 진단 확인
- [ ] 10초 경과 후 DNS 쿼리 행 갱신 확인
- [ ] `timeline.txt` 내용 정확성 확인
- [ ] 인간 검토 후 Phase 5 진행

---

### Phase 5: 종료 처리 + 리포트

---

#### Task 7: `New-SummaryReport` + 종료 핸들러

**Description:**  
요약 리포트 생성 함수(`New-SummaryReport`)와 종료 핸들러를 구현한다. `try/finally`로 Ctrl+C를 처리하고, `Register-EngineEvent PowerShell.Exiting`으로 창 닫기를 보완한다. `$script:ReportWritten` 플래그로 이중 실행을 방지한다.

**Acceptance criteria:**
- [ ] `report.txt` 내용: 기간, 소요 시간, 샘플 수
- [ ] `report.txt` 내용: 대상별 통계 (sent/received/비율/avg/min/max latency)
- [ ] `report.txt` 내용: DNS 쿼리 통계
- [ ] `report.txt` 내용: 장애 이벤트 목록 (시간, 대상, 연속 횟수, 진단)
- [ ] `report.txt` 내용: 구간 분석 요약 (유형별 건수/총 시간)
- [ ] `report.txt` 내용: traceroute.txt 참조 안내
- [ ] Ctrl+C 시 `report.txt` 생성 확인
- [ ] `$script:ReportWritten` 플래그로 중복 생성 방지

**Verification:**
- [ ] 30초 실행 후 Ctrl+C → `report.txt` 생성 및 내용 정확성 확인
- [ ] `report.txt`에 모든 섹션 포함 확인

**Dependencies:** Task 6

**Files:**
- `scripts/network_analyzer/main.ps1`

**Scope:** M

---

### Phase 6: 진입점 + 문서화

---

#### Task 8: `main.bat` 작성

**Description:**  
더블클릭으로 실행 가능한 BAT 진입점을 작성한다. `powershell -ExecutionPolicy Bypass -File "%~dp0main.ps1"`로 PS1을 실행한다. 종료 후 `pause`로 창이 즉시 닫히지 않도록 한다.

**Acceptance criteria:**
- [ ] 더블클릭 시 main.ps1 실행
- [ ] PS1 종료 후 "Press any key to continue..." 표시
- [ ] 스크립트 디렉토리 기준 상대 경로로 main.ps1 참조 (`%~dp0`)

**Verification:**
- [ ] `main.bat` 더블클릭 → PowerShell 창 열리고 main.ps1 실행 확인

**Dependencies:** Task 7

**Files:**
- `scripts/network_analyzer/main.bat` (신규)

**Scope:** XS

---

#### Task 9: `README.md` 작성

**Description:**  
스크립트 사용 가이드를 작성한다. 목적, 요구 사항, 실행 방법, 입력 예시, 대시보드 설명, 로그 파일 설명, 문제 해결 가이드를 포함한다.

**Acceptance criteria:**
- [ ] 실행 방법 (BAT 더블클릭 / PS1 직접 실행) 안내
- [ ] 입력 항목별 설명 및 예시 포함
- [ ] 생성 파일 (`timeline.txt`, `traceroute.txt`, `report.txt`) 설명
- [ ] 구간 진단 표 포함
- [ ] PowerShell 실행 정책 문제 해결 방법 포함

**Verification:**
- [ ] README 내용이 실제 구현과 일치하는지 확인

**Dependencies:** Task 8

**Files:**
- `scripts/network_analyzer/README.md` (신규)

**Scope:** S

---

### Checkpoint 3 (Final): 전체 검증

- [ ] 정상 실행 — 유효 IP 입력 → 대시보드, 3개 파일 생성
- [ ] 입력 오류 — 잘못된 IP → 재입력 프롬프트
- [ ] FAIL 감지 — 무효 IP → ✗ FAIL + 구간 진단
- [ ] Ctrl+C → report.txt 생성
- [ ] 추가 대상 스킵 — 2개 타겟만 표시
- [ ] 추가 대상 입력 — 4개 타겟 모두 표시
- [ ] DNS 쿼리 — 10초 후 [DNS] 로그 확인
- [ ] main.bat 더블클릭 실행 확인
- [ ] 모든 Success Criteria 충족

---

## Risks and Mitigations

| 리스크 | 영향 | 완화 방법 |
|--------|------|----------|
| 창 X버튼 종료 시 `finally` 미실행 (PS5.1 제약) | 높음 | `Register-EngineEvent PowerShell.Exiting` 추가 + 중복 방지 플래그 |
| `tracert` 출력이 로케일별로 헤더 텍스트 상이 | 낮음 | 헤더 파싱 없이 raw 저장, hop IP만 정규식으로 추출 |
| `Test-Connection` PS5 반환 객체 구조 (PS7과 다름) | 중간 | PS5 기준(`PingReply.ResponseTime`, `.TimeToLive`)으로 작성, `Select-Object -First 1` 활용 |
| 느린 tracert로 입력~모니터링 시작까지 지연 | 낮음 | `-w 3000` 타임아웃 설정 + 진행 상태 메시지 출력 |
| 대시보드 깜빡임 (`[Console]::Clear` 호출) | 낮음 | PS5에서 `[Console]::Clear()`는 허용 가능한 수준; 대안 없음 |

---

## Open Questions

없음.
