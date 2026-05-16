# Windows-EZ-Kit

Windows 운영 환경에서 유용하게 사용할 수 있는 다양한 스크립트 모음입니다.

## 프로젝트 소개

Windows Ez Kit은 Windows 서버/PC 관리자와 운영자를 위한 편리한 스크립트 도구 모음입니다. 시스템 모니터링, 네트워크 설정, 보안 점검, 자동화 작업 등 일상적인 운영 작업을 자동화하고 간소화하는 스크립트를 제공합니다.

## 스크립트 카탈로그

### 파일 관리

#### [Sort by Name](scripts/sort_by_name/)
배치 파일이 위치한 폴더의 파일을 이름순으로 정렬하여 `접두사_001` 형식으로 일괄 변경하는 스크립트입니다.

- **주요 기능**: 사용자 지정 접두사 입력, 이름순 정렬 후 일괄 변경, 원본 확장자 유지, 복원 스크립트 자동 생성
- **사용 사례**: 사진/영상 파일 일괄 정리, 문서 파일 순번 부여, 날짜 기준 촬영본 정렬
- **지원 환경**: Windows 10 / 11, Windows Server 2019 / 2022

## 다운로드

### 스크립트별 개별 다운로드

Git 없이 원하는 스크립트만 ZIP 파일로 바로 다운로드할 수 있습니다.

| 스크립트 | 다운로드 |
|---------|---------|
| Sort by Name | [ZIP 다운로드](https://download-directory.github.io/?url=https://github.com/HelloJamong/windows-ez-kit/tree/main/scripts/sort_by_name) |

> **참고**: 다운로드 링크는 [download-directory.github.io](https://download-directory.github.io) 서비스를 이용합니다.
> 브라우저에서 링크를 클릭하면 ZIP 파일이 자동으로 다운로드됩니다.

### 전체 스크립트 다운로드 (Git 사용)

```bat
git clone https://github.com/HelloJamong/windows-ez-kit.git
```

## 설치 방법

### 개별 스크립트 설치

각 스크립트 디렉토리의 README.md를 참조하세요.

## 시스템 요구사항

- Windows 10 / 11 (ANSI 컬러 출력 지원)
- Windows Server 2019 / 2022 (일부 스크립트)
- PowerShell 5.1 이상
- 관리자 권한 (스크립트에 따라 상이)

## 프로젝트 구조

```
windows-ez-kit/
├── README.md                           # 이 파일
├── export.bat                          # 스크립트 개별 ZIP 내보내기
├── scripts/                            # 모든 스크립트
│   └── sort_by_name/                   # 파일 이름순 정리
│       ├── main.bat
│       └── README.md
```

## 라이선스

MIT License
