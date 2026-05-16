# Changelog

Windows-EZ-Kit 전체 프로젝트의 변경 이력입니다.

---

## [Unreleased]

### Fixed
- `scripts/sort_by_name/main.bat`: 더블클릭 실행 중 초기 오류가 발생해도 창이 즉시 닫히지 않도록 실행 래퍼 추가
- `scripts/sort_by_name/main.bat`: PowerShell 기반 `for /f` 호출을 `usebackq` 형식으로 변경해 인용부호 충돌 가능성 완화

## [0.1.0] - 2026-05-16

### Added
- 프로젝트 기본 틀 구성 (linux-ez-kit 구조 기반 Windows 포팅)
- `export.bat`: `scripts/` 하위 폴더를 ZIP으로 `export/`에 저장하는 내보내기 스크립트
- `.gitattributes`: `*.bat` / `*.ps1` / `*.cmd` → CRLF, `*.md` → LF 설정
- `scripts/sort_by_name`: 파일 이름순 정렬 후 `접두사_001` 형식 일괄 변경 스크립트

### Fixed
- `export.bat`: `for /f` 구문 내 단따옴표 충돌로 실행 즉시 종료되는 버그 수정
