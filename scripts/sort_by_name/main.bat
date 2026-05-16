@echo off
setlocal EnableExtensions EnableDelayedExpansion

set "RED="
set "GREEN="
set "YELLOW="
set "CYAN="
set "BOLD="
set "NC="

set "SCRIPT_DIR=%~dp0"
set "SCRIPT_NAME=%~nx0"

pushd "%SCRIPT_DIR%" >nul 2>&1
if errorlevel 1 (
    echo.
    echo ERROR: Cannot enter the target folder.
    echo Target: !SCRIPT_DIR!
    echo.
    pause
    exit /b 1
)

set "RUN_ID=%RANDOM%_%RANDOM%_%RANDOM%"
set "BACKUP_DIR=_sort_backup"
set "RESTORE_FILE=%BACKUP_DIR%\restore_%RUN_ID%.bat"
set "TMP_PREFIX=__sbn_%RUN_ID%_"

call :main
set "EXIT_CODE=%errorlevel%"
popd >nul 2>&1
exit /b %EXIT_CODE%

:main
    call :print_banner
    call :get_prefix
    call :collect_files
    if "!FILE_COUNT!"=="0" (
        echo.
        echo   No files to rename.
        echo.
        pause
        exit /b 0
    )
    call :print_preview
    call :confirm
    if /i not "!CONFIRMED!"=="Y" (
        echo.
        echo   Canceled.
        echo.
        pause
        exit /b 0
    )
    call :rename_files
    call :print_done
    exit /b 0

:print_banner
    echo.
    echo ======================================================================
    echo        Sort by Name
    echo ======================================================================
    echo.
    echo   Rename files in this folder in name order.
    echo   Format: PREFIX_001.ext
    echo.
    echo   Target: !SCRIPT_DIR!
    echo.
    exit /b 0

:get_prefix
    set "PREFIX="
:prefix_loop
    set /p "PREFIX=  Enter prefix: "
    if not defined PREFIX (
        echo   Prefix is required.
        goto prefix_loop
    )
    exit /b 0

:collect_files
    set "FILE_COUNT=0"
    for /f "delims=" %%f in ('dir /b /o:n /a:-d 2^>nul') do (
        if /i not "%%f"=="%SCRIPT_NAME%" (
            set /a FILE_COUNT+=1
            set "FILE_!FILE_COUNT!=%%f"
            set "EXT_!FILE_COUNT!=%%~xf"
        )
    )
    set "PAD_WIDTH=3"
    if !FILE_COUNT! gtr 999 set "PAD_WIDTH=4"
    if !FILE_COUNT! gtr 9999 set "PAD_WIDTH=5"
    exit /b 0

:print_preview
    echo   Preview:
    echo.
    for /l %%i in (1,1,!FILE_COUNT!) do (
        set "ZEROS=000000000%%i"
        set "PADDED=!ZEROS:~-%PAD_WIDTH%!"
        echo     !FILE_%%i! -^> !PREFIX!_!PADDED!!EXT_%%i!
    )
    echo.
    echo   Total: !FILE_COUNT! file(s)
    echo.
    exit /b 0

:confirm
    set "CONFIRMED="
    set /p "CONFIRMED=  Continue? (Y/N): "
    if not defined CONFIRMED set "CONFIRMED=N"
    exit /b 0

:rename_files
    if not exist "%BACKUP_DIR%" mkdir "%BACKUP_DIR%"
    if not exist "%BACKUP_DIR%" (
        echo.
        echo   ERROR: Cannot create backup folder.
        echo.
        pause
        exit /b 1
    )

    (
        echo @echo off
        echo pushd "%%~dp0.."
        echo echo.
        echo echo Restoring original file names...
        echo echo.
    ) > "%RESTORE_FILE%"

    echo.
    echo   Renaming...
    echo.

    for /l %%i in (1,1,!FILE_COUNT!) do (
        ren "!FILE_%%i!" "!TMP_PREFIX!%%i!EXT_%%i!" 2>nul
    )

    set "RENAME_SUCCESS=0"
    set "RENAME_FAIL=0"
    for /l %%i in (1,1,!FILE_COUNT!) do (
        set "ZEROS=000000000%%i"
        set "PADDED=!ZEROS:~-%PAD_WIDTH%!"
        set "TEMP_NAME=!TMP_PREFIX!%%i!EXT_%%i!"
        set "NEW_NAME=!PREFIX!_!PADDED!!EXT_%%i!"
        set "ORIG=!FILE_%%i!"

        ren "!TEMP_NAME!" "!NEW_NAME!" 2>nul
        if !errorlevel! equ 0 (
            set /a RENAME_SUCCESS+=1
            echo ren "!NEW_NAME!" "!ORIG!" >> "%RESTORE_FILE%"
            echo   OK: !ORIG! -^> !NEW_NAME!
        ) else (
            set /a RENAME_FAIL+=1
            echo   FAIL: !ORIG!
        )
    )

    (
        echo echo.
        echo echo Restore complete.
        echo popd
        echo pause
    ) >> "%RESTORE_FILE%"

    exit /b 0

:print_done
    echo.
    echo ----------------------------------------------------------------------
    if "!RENAME_FAIL!"=="0" (
        echo   Done: !RENAME_SUCCESS! file(s) renamed.
    ) else (
        echo   Done: !RENAME_SUCCESS! succeeded, !RENAME_FAIL! failed.
    )
    echo   Restore script: !SCRIPT_DIR!!RESTORE_FILE!
    echo ======================================================================
    echo.
    pause
    exit /b 0
