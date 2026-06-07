# Network Analyzer

네트워크 연결 문제 발생 시 **어느 구간**에서 **어느 시점**에 장애가 발생했는지 분석하는 도구입니다.

## 기능

- Gateway, DNS, 인터넷, 사내 서버 등 최대 4개 대상을 1초 단위로 ICMP 모니터링
- 10초마다 DNS 쿼리 테스트 (실제 도메인 조회)
- 시작 시 각 대상에 Traceroute 1회 실행
- 실시간 콘솔 대시보드 (상태 / 지연 / 손실률 / 구간 진단 / 최근 이벤트)
- 종료 시 타임라인 로그 + 요약 리포트 자동 저장

## 요구 사항

- Windows 10 / 11, Windows Server 2019 / 2022
- PowerShell 5.1 이상

## 실행 방법

**방법 1 — BAT 더블클릭**
```
main.bat
```

**방법 2 — PowerShell 직접 실행**
```powershell
powershell -ExecutionPolicy Bypass -File ".\main.ps1"
```

## 입력 항목

| 순서 | 항목 | 필수 여부 | 예시 |
|------|------|----------|------|
| 1 | Gateway IP | 필수 | `192.168.1.1` |
| 2 | DNS IP | 필수 | `8.8.8.1` |
| 3 | DNS 쿼리 도메인 | 선택 (기본: `google.com`) | `naver.com` |
| 4 | 추가 대상 #1 | 선택 | `Internet 8.8.8.8` |
| 5 | 추가 대상 #2 | 선택 | `InternalSrv 10.0.0.100` |

추가 대상은 `레이블 IP` 형식으로 입력합니다. Enter를 누르면 스킵합니다.

## 대시보드 설명

```
╔════════════════════════════════════════════════════════════════════════╗
║  Network Connectivity Analyzer                                        ║
║  Started: 2026-06-05 10:30:00        Elapsed: 00:05:23               ║
╠════════════════════════════════════════════════════════════════════════╣
║  TARGET         IP              STATUS    LATENCY  LOSS%   SENT      ║
║  Gateway        192.168.1.1     ● OK       12ms    0.0%    323       ║
║  DNS            8.8.8.1         ● OK        8ms    0.0%    323       ║
║  Internet       8.8.8.8         ✗ FAIL      ---   15.3%    323       ║
╠════════════════════════════════════════════════════════════════════════╣
║  DNS Query  google.com via 8.8.8.1   ● OK  45ms  (33회 테스트)      ║
╠════════════════════════════════════════════════════════════════════════╣
║  SEGMENT DIAGNOSIS: GW:OK DNS:OK Net:FAIL — ISP / 업스트림 라우팅 문제 ║
╠════════════════════════════════════════════════════════════════════════╣
║  RECENT EVENTS (최근 5건)                                             ║
║  [10:35:01] Internet (8.8.8.8) FAIL 14회 (진행 중)                   ║
╚════════════════════════════════════════════════════════════════════════╝
```

## 구간 진단 기준

| 상태 | 진단 |
|------|------|
| GW FAIL | 로컬 네트워크 / 게이트웨이 문제 |
| GW OK + DNS FAIL | DNS 서버 문제 |
| GW OK + DNS OK + Internet FAIL | ISP / 업스트림 라우팅 문제 |
| GW OK + DNS OK + Internet OK + Custom FAIL | 사내 서버 문제 |
| 모두 OK | 정상 |

## 생성 파일

종료 후 `_network_analyzer_logs\YYYYMMDD_HHMMSS\` 폴더에 저장됩니다.

| 파일 | 내용 |
|------|------|
| `timeline.txt` | `[PING]` / `[DNS]` / `[TRACE]` / `[EVENT]` prefix가 포함된 통합 타임라인 |
| `traceroute.txt` | 시작 시 실행한 각 대상의 tracert 원본 출력 |
| `report.txt` | 대상별 통계, 장애 이벤트, 구간 분석 요약 |

## 종료 방법

- **Ctrl+C** 또는 **창 닫기(X)** — 모니터링 종료 후 `report.txt` 자동 생성

## 문제 해결

**"이 시스템에서 스크립트를 실행할 수 없습니다" 오류**
```powershell
powershell -ExecutionPolicy Bypass -File ".\main.ps1"
```
또는 `main.bat`으로 실행하세요.

**traceroute가 오래 걸리는 경우**
네트워크 환경에 따라 traceroute에 수십 초가 소요될 수 있습니다. 완료 후 모니터링이 시작됩니다.

**창 닫기 시 리포트가 생성되지 않는 경우**
PowerShell 5.1의 제약으로 창을 강제 종료하면 리포트 생성이 보장되지 않을 수 있습니다.
Ctrl+C로 종료하면 항상 리포트가 생성됩니다.
