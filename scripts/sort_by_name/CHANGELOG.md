# Changelog - Sort by Name

---

## [Unreleased]

## [0.1.0] - 2026-05-16

### Added
- 최초 릴리스
- 실행 폴더 내 파일을 이름 오름차순 정렬 후 `접두사_001` 형식으로 일괄 변경
- 실행 전 미리보기 및 사용자 확인 프롬프트
- 파일 수에 따른 자리수 자동 결정 (≤999: 3자리, ≤9999: 4자리, ≤99999: 5자리)
- 이름 충돌 방지를 위한 2단계 변경 (원본 → 임시명 → 최종명)
- 복원 스크립트 자동 생성 (`_sort_backup\restore_YYYYMMDD_HHMMSS.bat`)

### Fixed
- `for /f` 구문 내 단따옴표 충돌로 실행 즉시 창이 종료되는 버그 수정
  - `Get-Date -Format 'yyyyMMdd_HHmmss'` → `Get-Date -Format yyyyMMdd_HHmmss`
