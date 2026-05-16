@echo off

:: Explorer에서 더블클릭 실행 시 초기 구문/환경 오류가 나도 창이 바로 닫히지 않도록
:: 부모 cmd가 자식 실행 결과를 확인한 뒤 오류일 때만 pause 합니다.
if /i "%~1"=="--sbn-child" goto :sbn_child
"%ComSpec%" /D /C ""%~f0" --sbn-child"
set "EXIT_CODE=%errorlevel%"
if "%EXIT_CODE%"=="0" exit /b 0
echo.
echo   [오류] Sort by Name 실행 중 문제가 발생했습니다. 코드: %EXIT_CODE%
echo   위 메시지를 확인한 뒤 main.bat을 최신 버전으로 다시 복사해 보세요.
echo.
pause
exit /b %EXIT_CODE%

:sbn_child
shift /1

setlocal EnableExtensions EnableDelayedExpansion

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Sort by Name - 파일 이름순 정리
::
:: 사용법: main.bat
:: 목적:  배치 파일이 위치한 폴더의 파일을 이름순으로 정렬하여
::        "접두사_001" 형식으로 일괄 변경
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: ESC 문자 설정 (PowerShell 사용)
:: for /f의 command 구분자인 작은따옴표와 내부 PowerShell 인용부호가 충돌하지 않도록
:: usebackq/backtick 형식으로 실행합니다.
for /f "usebackq delims=" %%a in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "[char]27"`) do set "ESC=%%a"
if not defined ESC set "ESC="

set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "YELLOW=%ESC%[33m"
set "CYAN=%ESC%[36m"
set "BOLD=%ESC%[1m"
set "NC=%ESC%[0m"

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_NAME=%~nx0"
for /f "usebackq delims=" %%t in (`powershell -NoProfile -ExecutionPolicy Bypass -Command "Get-Date -Format 'yyyyMMdd_HHmmss'"`) do set "TIMESTAMP=%%t"
if not defined TIMESTAMP set "TIMESTAMP=00000000_000000"

set "BACKUP_DIR=%SCRIPT_DIR%_sort_backup"
set "RESTORE_FILE=%BACKUP_DIR%\restore_%TIMESTAMP%.bat"
set "TMP_PREFIX=__sbn_%TIMESTAMP%_"

call :main
set "EXIT_CODE=%errorlevel%"
exit /b %EXIT_CODE%

:: ==============================================================================
:main
    call :print_banner
    call :get_prefix
    if errorlevel 1 (
        echo.
        pause
        exit /b 1
    )
    call :collect_files
    if "!FILE_COUNT!"=="0" (
        echo.
        echo   %YELLOW%정리할 파일이 없습니다.%NC%
        echo.
        pause
        exit /b 0
    )
    call :print_preview
    call :confirm
    if /i not "!CONFIRMED!"=="Y" (
        echo.
        echo   %YELLOW%취소되었습니다.%NC%
        echo.
        pause
        exit /b 0
    )
    call :rename_files
    call :print_done
    exit /b 0

:: ==============================================================================
:print_banner
    echo.
    echo %BOLD%======================================================================%NC%
    echo %BOLD%       Sort by Name - 파일 이름순 정리%NC%
    echo %BOLD%======================================================================%NC%
    echo.
    echo   배치 파일이 위치한 폴더의 파일을 이름순으로 정렬하여
    echo   접두사_001 형식으로 일괄 변경합니다.
    echo.
    echo   대상 경로: %CYAN%%SCRIPT_DIR%%NC%
    echo.
    exit /b 0

:: ==============================================================================
:get_prefix
    :prefix_loop
    set "PREFIX="
    set /p "PREFIX=  접두사를 입력하세요 (예: 정리용): "
    if not defined PREFIX (
        echo   %RED%접두사를 입력해야 합니다.%NC%
        goto prefix_loop
    )
    exit /b 0

:: ==============================================================================
:collect_files
    set "FILE_COUNT=0"
    for /f "delims=" %%f in ('dir /b /o:n /a:-d "%SCRIPT_DIR%*" 2^>nul') do (
        if /i not "%%f"=="%SCRIPT_NAME%" (
            set /a FILE_COUNT+=1
            set "FILE_!FILE_COUNT!=%%f"
            set "EXT_!FILE_COUNT!=%%~xf"
        )
    )
    set "PAD_WIDTH=3"
    if !FILE_COUNT! gtr 999  set "PAD_WIDTH=4"
    if !FILE_COUNT! gtr 9999 set "PAD_WIDTH=5"
    exit /b 0

:: ==============================================================================
:print_preview
    echo %BOLD%  [미리보기] 다음과 같이 파일이 변경됩니다:%NC%
    echo.
    for /l %%i in (1,1,!FILE_COUNT!) do (
        set "ZEROS=000000000%%i"
        set "PADDED=!ZEROS:~-%PAD_WIDTH%!"
        echo     !FILE_%%i! %CYAN%-^>%NC% !PREFIX!_!PADDED!!EXT_%%i!
    )
    echo.
    echo   %BOLD%총 !FILE_COUNT!개 파일을 정리합니다.%NC%
    echo.
    exit /b 0

:: ==============================================================================
:confirm
    set "CONFIRMED="
    set /p "CONFIRMED=  계속하시겠습니까? (Y/N): "
    if not defined CONFIRMED set "CONFIRMED=N"
    exit /b 0

:: ==============================================================================
:rename_files
    if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"

    (
        echo @echo off
        echo echo.
        echo echo 원본 파일명으로 복원합니다...
        echo echo.
    ) > "%RESTORE_FILE%"

    echo.
    echo %BOLD%  [변경 중...]%NC%
    echo.

    :: 1단계: 임시 이름으로 변경 (이름 충돌 방지)
    for /l %%i in (1,1,!FILE_COUNT!) do (
        ren "%SCRIPT_DIR%!FILE_%%i!" "%TMP_PREFIX%%%i!EXT_%%i!" 2>nul
    )

    :: 2단계: 최종 이름으로 변경 및 복원 스크립트 작성
    set "RENAME_SUCCESS=0"
    set "RENAME_FAIL=0"
    for /l %%i in (1,1,!FILE_COUNT!) do (
        set "ZEROS=000000000%%i"
        set "PADDED=!ZEROS:~-%PAD_WIDTH%!"
        set "TEMP_NAME=%TMP_PREFIX%%%i!EXT_%%i!"
        set "NEW_NAME=!PREFIX!_!PADDED!!EXT_%%i!"
        set "ORIG=!FILE_%%i!"

        ren "%SCRIPT_DIR%!TEMP_NAME!" "!NEW_NAME!" 2>nul
        if !errorlevel! equ 0 (
            set /a RENAME_SUCCESS+=1
            echo ren "%SCRIPT_DIR%!NEW_NAME!" "!ORIG!" >> "%RESTORE_FILE%"
            echo   %GREEN%완료%NC%: !ORIG! %CYAN%-^>%NC% !NEW_NAME!
        ) else (
            set /a RENAME_FAIL+=1
            echo   %RED%실패%NC%: !ORIG! 변경 실패
        )
    )

    (
        echo echo.
        echo echo 복원이 완료되었습니다.
        echo pause
    ) >> "%RESTORE_FILE%"

    exit /b 0

:: ==============================================================================
:print_done
    echo.
    echo %BOLD%----------------------------------------------------------------------%NC%
    if "!RENAME_FAIL!"=="0" (
        echo   %GREEN%완료: !RENAME_SUCCESS!개 파일 변경 완료%NC%
    ) else (
        echo   %YELLOW%완료: !RENAME_SUCCESS!개 성공, !RENAME_FAIL!개 실패%NC%
    )
    echo   복원 스크립트: %CYAN%%RESTORE_FILE%%NC%
    echo %BOLD%======================================================================%NC%
    echo.
    pause
    exit /b 0
