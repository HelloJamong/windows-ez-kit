# Netstat Status Monitor - 포트 연결 상태 로그 기록

Windows PC에서 지정한 포트의 `netstat -an` 결과를 1초 단위로 확인하고, `ESTABLISHED` 상태가 사라지는 시점을 로그에 남기는 PowerShell 스크립트입니다.

## 주요 기능

- 실행 시 스캔할 포트 번호 입력
- 1초마다 `netstat -an | findstr "포트"` 형태로 현재 포트 연결 상태 확인
- `ESTABLISHED` 행이 없으면 `[NOT_ESTABLISHED]` 표시
- 로그를 `C:\Temp\날짜_시작시간_포트_status.txt` 형식으로 저장
- 실행 중 Windows의 자동 절전 진입 방지
- 창을 닫거나 `Ctrl+C`로 중단하기 전까지 계속 실행

## 사용 방법

```powershell
# PowerShell 콘솔에서 실행
.\main.ps1

# 실행 정책 오류 시
powershell -ExecutionPolicy Bypass -File ".\main.ps1"
```

1. 스크립트를 실행합니다.
2. 스캔할 포트 번호를 입력합니다. 예: `443`
3. 로그 파일 경로를 확인합니다.
4. 중지하려면 실행 창을 닫거나 `Ctrl+C`를 누릅니다.

## 로그 파일

로그는 `C:\Temp` 아래에 저장됩니다.

```text
C:\Temp\20260527_143000_443_status.txt
```

## 로그 형식

파일 맨 위에는 최초 실행 시간이 기록됩니다.

```text
Start Time: 2026-05-27 14:30:00
Port: 443
Command: netstat -an | findstr "443"
Log File: C:\Temp\20260527_143000_443_status.txt
Interval: 1 second
Sleep Prevention: enabled while this script is running
----------------------------------------------------------------------
14:30:01 - TCP    192.168.0.10:52341    203.0.113.10:443    ESTABLISHED
14:30:02 - TCP    192.168.0.10:52341    203.0.113.10:443    TIME_WAIT
14:30:02 - [NOT_ESTABLISHED] no ESTABLISHED rows for port 443
14:30:03 - [NOT_ESTABLISHED] no netstat rows for port 443
```

## 절전 모드 관련 주의사항

스크립트 실행 중에는 Windows API를 사용해 자동 절전 진입을 방지합니다.

다만 사용자가 직접 절전 버튼을 누르거나, 노트북 덮개 닫기 정책, 강제 전원 정책 등으로 실제 절전 상태에 들어가면 Windows 프로세스 자체가 일시 중지될 수 있습니다. 이 경우 깨어난 뒤 스크립트가 이어서 실행됩니다.

## 주의사항

- 포트 입력은 `1~65535` 사이의 숫자만 허용합니다.
- `findstr "포트"` 방식이므로 입력한 포트 문자열이 포함된 모든 `netstat` 행이 기록됩니다.
- 로그 파일은 계속 커질 수 있으므로 장시간 실행 시 디스크 여유 공간을 확인하세요.
- 관리자 권한은 일반적인 `netstat -an` 조회에는 필요하지 않습니다.

## 지원 환경

- Windows 10 / 11
- Windows Server 2019 / 2022
- PowerShell 5.1 이상
