# Changelog

Windows-EZ-Kit 전체 프로젝트의 변경 이력입니다.

---

## [Unreleased]

### Fixed
- `scripts/sort_by_name/main.bat`: 즉시 종료 원인이 될 수 있는 초기 PowerShell/ANSI 색상 초기화 제거
- `scripts/sort_by_name/README.md`: 관리자 권한 필요 여부 안내 추가
- `scripts/sort_by_name/main.bat`: 실행 폴더 경로에 `)` 같은 괄호가 포함되면 배치 블록 파싱이 깨지는 문제 수정
- `scripts/sort_by_name/main.bat`: PowerShell 의존성을 제거하고 복원 스크립트 이름을 랜덤 접미사 기반으로 변경
- `scripts/sort_by_name/main.bat`: UTF-8 코드 페이지를 설정해 한글 안내문이 깨지는 문제 완화
- `scripts/sort_by_name/main.bat`: `cmd.exe` 코드페이지/파서 문제를 피하기 위해 ASCII-only로 변경

## [0.1.0] - 2026-05-16

### Added
- 프로젝트 기본 틀 구성 (linux-ez-kit 구조 기반 Windows 포팅)
- `export.bat`: `scripts/` 하위 폴더를 ZIP으로 `export/`에 저장하는 내보내기 스크립트
- `.gitattributes`: `*.bat` / `*.ps1` / `*.cmd` → CRLF, `*.md` → LF 설정
- `scripts/sort_by_name`: 파일 이름순 정렬 후 `접두사_001` 형식 일괄 변경 스크립트

### Fixed
- `export.bat`: `for /f` 구문 내 단따옴표 충돌로 실행 즉시 종료되는 버그 수정
