@echo off
setlocal EnableDelayedExpansion

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Windows-EZ-Kit - 프로젝트 내보내기 스크립트
::
:: 사용법: export.bat
:: 목적:  특정 스크립트를 선택하여 ZIP으로 압축 후 export\ 폴더에 저장
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: ANSI 색상 초기화 (Windows 10 1511+)
for /f "delims=" %%a in ('echo prompt $E^| cmd') do set "ESC=%%a"
set "RED=%ESC%[31m"
set "GREEN=%ESC%[32m"
set "CYAN=%ESC%[36m"
set "BOLD=%ESC%[1m"
set "NC=%ESC%[0m"

set "SCRIPT_DIR=%~dp0"
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format yyyyMMdd_HHmmss"') do set "TIMESTAMP=%%t"
set "EXPORT_DIR=%SCRIPT_DIR%export"

:: ------------------------------------------------------------------------------
:: 사용 가능한 프로젝트 목록 수집
:: ------------------------------------------------------------------------------
set "PROJ_COUNT=0"
for /d %%d in ("%SCRIPT_DIR%scripts\*") do (
    set /a PROJ_COUNT+=1
    set "PROJ_!PROJ_COUNT!=%%~nd"
)

if "%PROJ_COUNT%"=="0" (
    echo.
    echo   %RED%scripts\ 폴더에 내보낼 프로젝트가 없습니다.%NC%
    echo.
    pause
    exit /b 1
)

call :print_banner
call :select_project
call :do_export
exit /b 0

:: ------------------------------------------------------------------------------
:: 배너
:: ------------------------------------------------------------------------------
:print_banner
echo.
echo %BOLD%======================================================================%NC%
echo %BOLD%       Windows-EZ-Kit - 프로젝트 내보내기%NC%
echo %BOLD%======================================================================%NC%
echo.
exit /b 0

:: ------------------------------------------------------------------------------
:: 프로젝트 선택 메뉴
:: ------------------------------------------------------------------------------
:select_project
echo %BOLD%  내보낼 프로젝트를 선택하세요:%NC%
echo.
for /l %%i in (1,1,%PROJ_COUNT%) do (
    echo     %CYAN%[%%i]%NC% !PROJ_%%i!
)
set /a ALL_IDX=%PROJ_COUNT%+1
echo     %CYAN%[%ALL_IDX%]%NC% 전체 (모든 프로젝트)
echo.

:input_loop
set "CHOICE="
set /p "CHOICE=  번호 입력 [1-%ALL_IDX%]: "
if not defined CHOICE goto input_loop
set /a CHOICE_NUM=%CHOICE% 2>nul
if %CHOICE_NUM% lss 1 goto input_invalid
if %CHOICE_NUM% gtr %ALL_IDX% goto input_invalid
set "SELECTED=%CHOICE_NUM%"
exit /b 0

:input_invalid
echo   %RED%1~%ALL_IDX% 사이의 숫자를 입력하세요.%NC%
goto input_loop

:: ------------------------------------------------------------------------------
:: 내보내기 실행
:: ------------------------------------------------------------------------------
:do_export
if not exist "%EXPORT_DIR%" mkdir "%EXPORT_DIR%"
echo.
echo %BOLD%----------------------------------------------------------------------%NC%

if "%SELECTED%"=="%ALL_IDX%" (
    echo   대상: %CYAN%전체 프로젝트 ^(%PROJ_COUNT%개^)%NC%
    echo.
    set "SUCCESS=0"
    for /l %%i in (1,1,%PROJ_COUNT%) do (
        call :export_one "!PROJ_%%i!"
        if !errorlevel! equ 0 set /a SUCCESS+=1
    )
    echo.
    echo %BOLD%----------------------------------------------------------------------%NC%
    echo   %GREEN%완료: !SUCCESS!/%PROJ_COUNT%개 프로젝트 내보내기 완료%NC%
) else (
    set "TARGET=!PROJ_%SELECTED%!"
    echo   대상: %CYAN%!TARGET!%NC%
    echo.
    call :export_one "!TARGET!"
    echo.
    echo %BOLD%----------------------------------------------------------------------%NC%
    echo   %GREEN%완료%NC%
)

echo.
echo   저장 위치: %CYAN%%EXPORT_DIR%\%NC%
echo %BOLD%======================================================================%NC%
echo.
pause
exit /b 0

:: ------------------------------------------------------------------------------
:: 단일 프로젝트 압축
:: ------------------------------------------------------------------------------
:export_one
set "PROJ_NAME=%~1"
set "SRC=%SCRIPT_DIR%scripts\%PROJ_NAME%"
set "OUT=%EXPORT_DIR%\%PROJ_NAME%_%TIMESTAMP%.zip"

echo   압축 중: %CYAN%%PROJ_NAME%%NC% ^→ %OUT%

powershell -NoProfile -Command ^
    "Compress-Archive -Path '%SRC%\*' -DestinationPath '%OUT%' -Force" 2>nul

if %errorlevel% equ 0 (
    for /f %%s in ('powershell -NoProfile -Command "[math]::Round((Get-Item '%OUT%').length / 1KB, 1)"') do set "SIZE=%%s"
    echo   %GREEN%완료%NC%: %OUT% ^(!SIZE! KB^)
    exit /b 0
) else (
    echo   %RED%실패%NC%: %PROJ_NAME% 압축 중 오류 발생
    exit /b 1
)
