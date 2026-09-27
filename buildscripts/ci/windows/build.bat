@echo off
SETLOCAL DisableDelayedExpansion
ECHO "MuseScore build"

SET "ARTIFACTS_DIR=build.artifacts"
SET "INSTALL_DIR=../build.install"
SET "BUILD_NUMBER="
SET "CRASH_LOG_SERVER_URL="
SET "TARGET_PROCESSOR_BITS=64"
SET "BUILD_CRASHPAD_CLIENT=OFF"
SET "BUILD_WIN_PORTABLE=OFF"

REM Each option consumes exactly one value. Commands after an ungrouped IF's
REM ampersand are unconditional; keep all shifts and assignments in their branch.
:GETOPTS
IF "%~1" == "" GOTO VALIDATE_OPTIONS
IF /I "%~1" == "-n" GOTO NUMBER_OPTION
IF /I "%~1" == "-b" GOTO BITS_OPTION
IF /I "%~1" == "--crash_log_url" GOTO CRASH_OPTION
IF /I "%~1" == "--portable" GOTO PORTABLE_OPTION
ECHO "error: unknown build option"
EXIT /b 1

:NUMBER_OPTION
IF "%~2" == "" EXIT /b 1
SET "BUILD_NUMBER=%~2"
SHIFT
SHIFT
GOTO GETOPTS

:BITS_OPTION
IF "%~2" == "" EXIT /b 1
SET "TARGET_PROCESSOR_BITS=%~2"
SHIFT
SHIFT
GOTO GETOPTS

:CRASH_OPTION
REM The workflow deliberately passes an empty quoted URL when no secret exists.
REM Keep Crashpad off in that case instead of enabling an unconfigured client.
SET "CRASH_LOG_SERVER_URL=%~2"
SET "BUILD_CRASHPAD_CLIENT=OFF"
IF NOT "%~2" == "" SET "BUILD_CRASHPAD_CLIENT=ON"
SHIFT
SHIFT
GOTO GETOPTS

:PORTABLE_OPTION
IF "%~2" == "" EXIT /b 1
SET "BUILD_WIN_PORTABLE=%~2"
SHIFT
SHIFT
GOTO GETOPTS

:VALIDATE_OPTIONS
IF NOT DEFINED BUILD_NUMBER (
    ECHO "error: not set BUILD_NUMBER"
    EXIT /b 1
)
FOR /F "delims=0123456789" %%N IN ("%BUILD_NUMBER%") DO EXIT /b 1
IF NOT "%TARGET_PROCESSOR_BITS%" == "64" IF NOT "%TARGET_PROCESSOR_BITS%" == "32" (
    ECHO "error: TARGET_PROCESSOR_BITS must be 32 or 64"
    EXIT /b 1
)
IF /I NOT "%BUILD_WIN_PORTABLE%" == "ON" IF /I NOT "%BUILD_WIN_PORTABLE%" == "OFF" (
    ECHO "error: BUILD_WIN_PORTABLE must be ON or OFF"
    EXIT /b 1
)

SET /p BUILD_MODE=<%ARTIFACTS_DIR%\env\build_mode.env
SET "MUSE_APP_BUILD_MODE=dev"
IF %BUILD_MODE% == devel   ( SET "MUSE_APP_BUILD_MODE=dev" ) ELSE (
IF %BUILD_MODE% == nightly ( SET "MUSE_APP_BUILD_MODE=dev" ) ELSE (
IF %BUILD_MODE% == testing ( SET "MUSE_APP_BUILD_MODE=testing" ) ELSE (
IF %BUILD_MODE% == stable  ( SET "MUSE_APP_BUILD_MODE=release" ) ELSE (
    ECHO "error: unknown BUILD_MODE: %BUILD_MODE%"
    EXIT /b 1
))))

ECHO "MUSE_APP_BUILD_MODE: %MUSE_APP_BUILD_MODE%"
ECHO "BUILD_NUMBER: %BUILD_NUMBER%"
ECHO "TARGET_PROCESSOR_BITS: %TARGET_PROCESSOR_BITS%"
ECHO "BUILD_CRASHPAD_CLIENT: %BUILD_CRASHPAD_CLIENT%"
ECHO "BUILD_WIN_PORTABLE: %BUILD_WIN_PORTABLE%"

XCOPY "C:\musescore_dependencies" "%CD%" /E /I /Y
ECHO "Finished copy dependencies"

SET "JACK_DIR=C:\Program Files (x86)\Jack"
SET "PATH=%JACK_DIR%;%PATH%"

SET "MUSESCORE_BUILD_CONFIGURATION=app"
IF /I "%BUILD_WIN_PORTABLE%" == "ON" (
    SET "INSTALL_DIR=../build.install/App/MuseScore"
    SET "MUSESCORE_BUILD_CONFIGURATION=app-portable"
)

bash ./buildscripts/ci/tools/make_revision_env.sh || EXIT /b 1
SET /p MUSESCORE_REVISION=<%ARTIFACTS_DIR%\env\build_revision.env

SET "MUSESCORE_BUILD_NUMBER=%BUILD_NUMBER%"
SET "MUSESCORE_INSTALL_DIR=%INSTALL_DIR%"
SET "MUSESCORE_CRASHREPORT_URL=%CRASH_LOG_SERVER_URL%"
SET "MUSESCORE_BUILD_CRASHPAD_CLIENT=%BUILD_CRASHPAD_CLIENT%"
SET "MUSESCORE_BUILD_VST_MODULE=ON"
SET "MUSESCORE_BUILD_WEBSOCKET=ON"

CALL ninja_build.bat -t installrelwithdebinfo || EXIT /b 1

bash ./buildscripts/ci/tools/make_release_channel_env.sh -c %MUSE_APP_BUILD_MODE% || EXIT /b 1
bash ./buildscripts/ci/tools/make_version_env.sh %BUILD_NUMBER% || EXIT /b 1
bash ./buildscripts/ci/tools/make_branch_env.sh || EXIT /b 1
EXIT /b 0
