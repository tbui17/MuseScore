#!/usr/bin/env pwsh
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# Fork Windows build helper: sets up the MSVC/Qt environment for the checked
# driver <SourceDirectory>/ninja_build.ps1 and runs its normal install flow.
#
#   pwsh -File buildscripts/ci/fork/windows-build.ps1 `
#     -SourceDirectory ./source -OutputDirectory ./build-output `
#     -ProvenancePath ./provenance/provenance.json `
#     -SourceSha <40-hex> -BuildNumber <run number> [-SourceRef <ref>]
#
# Output contract for the packaging helper:
#   <OutputDirectory>/install   CMake install staging tree (package input)
#   <OutputDirectory>/logs      driver log
#   -ProvenancePath             toolchain, application version, channel,
#                               architecture, build type and the CMake cache
#                               feature values that were actually configured
#
# Recipe (fixed): RelWithDebInfo full desktop app via `-t installrelwithdebinfo
# -j 4`, audio export + ASIO + VST + websocket + accessibility + braille on,
# crash upload off, update module off, and the soundfont pinned to the payload
# committed in the source tree (no S3 refresh). Trusted runs may opt into the
# explicitly provisioned compiler-object and dependency-archive caches.
#
# Deliberately not used: buildscripts/ci/windows/setup.bat and build.bat. The
# legacy path deletes C:\TEMP, downloads unverified payloads and enables
# Crashpad for an empty crash URL; dependencies come from the CMake dependency
# bootstrap (Qt is installed by the workflow before this script runs).

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string] $SourceDirectory,

    [Parameter(Mandatory = $true)]
    [string] $OutputDirectory,

    [Parameter(Mandatory = $true)]
    [string] $ProvenancePath,

    # Full application commit checked out in -SourceDirectory. Must match git HEAD;
    # the driver's placeholder defaults are never used.
    [Parameter(Mandatory = $true)]
    [string] $SourceSha,

    # Run number, at most 9 digits so it fits the Int32 packaging limit.
    [Parameter(Mandatory = $true)]
    [string] $BuildNumber,

    # Recorded in provenance only.
    [string] $SourceRef = "",

    # Compiler-object caching. Trusted workflow runs enable it after the cold gate; the workflow
    # always passes an explicit directory so this helper never guesses a cache location.
    [switch] $UseCache,

    [string] $CcacheDirectory = "",

    # Print the cache identity (toolchain, SDK, CMake, Qt, dependency lock, build flags, ccache) as
    # one JSON line and exit without building, so the workflow derives cache keys from the same
    # measurements this helper enforces during the build.
    [switch] $CacheIdentityOnly
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
$ProgressPreference = "SilentlyContinue"

$DriverTarget = "installrelwithdebinfo"
$Jobs = 4
$BuildType = "RelWithDebInfo"
$Channel = "dev"
$Architecture = "x64"
$Int32Max = [int]::MaxValue
$PinnedCcacheVersion = "4.13.6"
$CcacheSchema = "1"
$CcacheMaxSize = "4G"
$QtModules = "qt5compat qtnetworkauth qtshadertools qtwebsockets"
$DetectedCcacheVersion = ""
$cacheIdentity = [ordered]@{}
$ccacheStatsSummary = [ordered]@{}

if ($UseCache -and [string]::IsNullOrWhiteSpace($CcacheDirectory)) {
    throw "-UseCache requires -CcacheDirectory: a cache directory must be explicit and helper-owned."
}
if (-not $UseCache -and -not [string]::IsNullOrWhiteSpace($CcacheDirectory)) {
    throw "-CcacheDirectory was passed without -UseCache; a cold build must not receive a cache directory."
}

function Write-Step {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Host ""
    Write-Host "== $Message" -ForegroundColor Cyan
}

function Get-EnvOrNull {
    param([Parameter(Mandatory = $true)][string] $Name)

    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    return $value.Trim()
}

function Get-FullPath {
    param([Parameter(Mandatory = $true)][string] $Path)
    return [IO.Path]::GetFullPath($Path)
}

function Test-PathInside {
    param(
        [Parameter(Mandatory = $true)][string] $Parent,
        [Parameter(Mandatory = $true)][string] $Child
    )

    $parentWithSeparator = (Get-FullPath $Parent).TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    return (Get-FullPath $Child).StartsWith($parentWithSeparator, [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-Tool {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $Arguments,
        [Parameter(Mandatory = $true)][string] $Purpose
    )

    $output = & $FilePath @Arguments 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "$Purpose failed with exit code $LASTEXITCODE`n> $FilePath $($Arguments -join ' ')`n$output"
    }

    return $output.Trim()
}

function Resolve-Tool {
    param([Parameter(Mandatory = $true)][string] $Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "$Name was not found on PATH."
    }

    if ($command.Source) {
        return $command.Source
    }

    return $command.Path
}

function Get-ReportedVersion {
    param(
        [Parameter(Mandatory = $true)][string] $FilePath,
        [Parameter(Mandatory = $true)][string[]] $VersionArguments
    )

    $firstLine = @((Invoke-Tool -FilePath $FilePath -Arguments $VersionArguments -Purpose "$FilePath $($VersionArguments -join ' ')") -split "`r?`n")[0]
    return ([regex]::Match($firstLine, '\d+(\.\d+)+')).Value
}
function Get-MsvcCompilerVersion {
    param([Parameter(Mandatory = $true)][string] $FilePath)

    # cl /Bv prints the authoritative banner before reporting D8003 because no source file
    # was supplied. Accept only that documented missing-source result; any other nonzero exit
    # means the compiler probe itself failed.
    $output = & $FilePath "/Bv" 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    $match = [regex]::Match($output, '(?im)^\s*Microsoft \(R\) C/C\+\+ Optimizing Compiler Version (?<version>\d+(?:\.\d+)+) for (?<arch>\S+)')
    if (-not $match.Success) {
        throw "cl.exe at '$FilePath' did not report an MSVC compiler banner through /Bv."
    }
    if ($match.Groups["arch"].Value -ne "x64") {
        throw "cl.exe at '$FilePath' reported target '$($match.Groups["arch"].Value)' instead of x64."
    }
    if ($exitCode -ne 0 -and $output -notmatch '(?im)D8003\s*:\s*missing source filename') {
        throw "cl.exe /Bv failed with exit code $exitCode after reporting its banner: $output"
    }
    Write-Host "cl.exe /Bv banner: $($match.Groups["version"].Value) for $($match.Groups["arch"].Value) (exit $exitCode)"
    return $match.Groups["version"].Value
}

function Import-MsvcEnvironment {
    param([Parameter(Mandatory = $true)][string] $InstallationPath)

    $vcvars = Join-Path $InstallationPath "VC\Auxiliary\Build\vcvars64.bat"
    if (-not (Test-Path -LiteralPath $vcvars)) {
        throw "vcvars64.bat was not found at '$vcvars'."
    }

    # cmd /s /c "<command>" keeps a quoted path with spaces intact.
    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $env:ComSpec
    $startInfo.Arguments = '/s /c "call "' + $vcvars + '" >nul 2>&1 && set"'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true

    $process = [System.Diagnostics.Process]::Start($startInfo)
    $rawOutput = $process.StandardOutput.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "vcvars64.bat failed with exit code $($process.ExitCode): $vcvars"
    }

    foreach ($line in ($rawOutput -split "`r?`n")) {
        if (($line -match '^([^=]+)=(.*)$') -and (-not $Matches[1].StartsWith("="))) {
            [Environment]::SetEnvironmentVariable($Matches[1], $Matches[2])
        }
    }

    if (-not ($env:VCToolsVersion -and $env:VSCMD_ARG_TGT_ARCH)) {
        throw "vcvars64.bat did not initialise the MSVC environment (VCToolsVersion/VSCMD_ARG_TGT_ARCH missing): $vcvars"
    }

    Write-Host "MSVC environment imported from $vcvars"
}

function Resolve-QtRoot {
    $candidates = @()
    if ($env:QT_ROOT_DIR) {
        $candidates += $env:QT_ROOT_DIR
    }
    if ($env:Qt6_DIR) {
        $candidates += (Join-Path $env:Qt6_DIR "..\..\..")
    }

    foreach ($candidate in $candidates) {
        $root = Get-FullPath $candidate
        if (Test-Path -LiteralPath (Join-Path $root "lib\cmake\Qt6\Qt6Config.cmake")) {
            return $root
        }
    }

    throw "No Qt 6 installation was found. Set QT_ROOT_DIR or Qt6_DIR (the workflow installs Qt before this step)."
}

function Get-CMakeCacheValues {
    param([Parameter(Mandatory = $true)][string] $CachePath)

    if (-not (Test-Path -LiteralPath $CachePath)) {
        throw "CMakeCache.txt was not found at '$CachePath'; the configure step did not run."
    }

    $values = @{}
    foreach ($line in [IO.File]::ReadAllLines($CachePath)) {
        $separator = $line.IndexOf("=")
        if ($line.StartsWith("//") -or $separator -lt 1) {
            continue
        }

        $key = $line.Substring(0, $separator)
        $typeSeparator = $key.IndexOf(":")
        if ($typeSeparator -lt 1) {
            continue
        }

        $values[$key.Substring(0, $typeSeparator)] = $line.Substring($separator + 1)
    }

    return $values
}

function Assert-CacheValue {
    param(
        [Parameter(Mandatory = $true)][hashtable] $Cache,
        [Parameter(Mandatory = $true)][string] $Key,
        [Parameter(Mandatory = $true)][string] $Expected,
        [bool] $Required = $true
    )

    if (-not $Cache.ContainsKey($Key)) {
        if ($Required) {
            throw "CMakeCache is missing the required fork release entry '$Key'."
        }
        return $null
    }

    $actual = $Cache[$Key]
    if ($actual -ne $Expected) {
        throw "Build metadata mismatch: CMakeCache entry '$Key' is '$actual' but the fork release contract requires '$Expected'."
    }

    return $actual
}
function Assert-Ccache {
    param([Parameter(Mandatory = $true)][string] $Directory)

    $command = Get-Command ccache -ErrorAction SilentlyContinue
    if (-not $command) {
        throw "ccache was not found on PATH although compiler caching is enabled."
    }
    $path = if ($command.Source) { $command.Source } else { $command.Path }
    $path = Get-FullPath $path
    $reported = Get-ReportedVersion -FilePath $path -VersionArguments @("--version")
    if (-not $reported) {
        throw "ccache at '$path' did not report a version."
    }
    if ([version]$reported -lt [version]"4.10") {
        throw "ccache $reported is older than the required 4.10 (MSVC /Z7 PCH support)."
    }
    if ([version]$reported -ne [version]$PinnedCcacheVersion) {
        throw "ccache $reported does not match the pinned $PinnedCcacheVersion; update the pin deliberately."
    }
    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Force -Path $Directory | Out-Null
    }
    Write-Host "ccache: $path ($reported, dir $Directory, max $CcacheMaxSize)"
    $script:DetectedCcacheVersion = "$reported"
    return $path
}

function Write-CcacheStats {
    param([Parameter(Mandatory = $true)][string] $Phase)

    $output = & ccache -s 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw "ccache statistics failed during '$Phase' with exit code $LASTEXITCODE.`n$output"
    }
    $statsPath = Join-Path $LogDirectory "ccache-stats-$Phase.log"
    [IO.File]::WriteAllText($statsPath, $output, (New-Object System.Text.UTF8Encoding($false)))
    $summary = [ordered]@{
        phase          = $Phase
        timestamp_utc  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        stats_log      = $statsPath
    }
    foreach ($field in @("Hits", "Misses", "Cache size", "Max cache size")) {
        $match = [regex]::Match($output, "(?m)^\s*" + [regex]::Escape($field) + "\s*:?\s*(.+?)\s*$")
        if ($match.Success) {
            $summary[$field] = $match.Groups[1].Value.Trim()
        }
    }
    $summaryText = ($summary.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ", "
    Write-Host "ccache stats ($Phase): $summaryText"
    return $summary
}

function Get-CacheIdentity {
    $lockPath = Join-Path $SourceDirectory "muse/buildscripts/cmake/deps/dependencies.lock.cmake"
    if (-not (Test-Path -LiteralPath $lockPath)) {
        throw "The dependency lock was not found at '$lockPath'; cache keys require it."
    }
    $lockSha = (Get-FileHash -LiteralPath $lockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $flagsText = ($cacheFlags.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ";"
    $temp = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllText($temp, $flagsText, (New-Object System.Text.UTF8Encoding($false)))
        $flagsSha = (Get-FileHash -LiteralPath $temp -Algorithm SHA256).Hash.ToLowerInvariant()
    } finally {
        Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue
    }

    $cmakeParts = @("$cmakeVersion".Split("."))
    $cmakeName = if ($cmakeParts.Count -ge 2) { "$($cmakeParts[0]).$($cmakeParts[1])" } else { "$cmakeVersion" }
    $moduleToken = (($QtModules -split " ") | Where-Object { $_ } | ForEach-Object { $_ }) -join "-"
    $sdkVersion = "$($env:WindowsSDKVersion)".TrimEnd([char]0x5C)
    $identity = [ordered]@{
        schema            = $CcacheSchema
        ccache_version    = $DetectedCcacheVersion
        visual_studio     = "$($visualStudio.InstallationVersion)"
        vctools_version   = "$($env:VCToolsVersion)"
        cl_version        = "$clVersion"
        windows_sdk       = $sdkVersion
        cmake             = $cmakeName
        ninja             = $ninjaVersion
        qt                = $qtVersion
        qt_modules        = $QtModules
        lock_sha256       = $lockSha
        flags_sha256      = $flagsSha
    }
    $requiredFields = @(
        "schema", "ccache_version", "visual_studio", "vctools_version", "cl_version",
        "windows_sdk", "cmake", "ninja", "qt", "qt_modules", "lock_sha256", "flags_sha256"
    )
    $missingFields = @($requiredFields | Where-Object {
        $value = $identity[$_]
        $null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)
    })
    if ($missingFields.Count -gt 0) {
        throw "Compiler-cache identity resolved empty fields: $($missingFields -join ', ')."
    }
    foreach ($hashField in @("lock_sha256", "flags_sha256")) {
        if ($identity[$hashField] -notmatch '^[0-9a-f]{64}$') {
            throw "Compiler-cache identity field '$hashField' is not a lowercase SHA-256."
        }
    }
    $identityBase = "ccache-v$CcacheSchema-win-x64-vs$($identity.visual_studio)-msvc$($identity.vctools_version)-cl$($identity.cl_version)-sdk$sdkVersion-qt$($identity.qt)-modules$moduleToken-cmake$cmakeName-ninja$($identity.ninja)-$BuildType-lock$lockSha-flags$flagsSha-ccache$($identity.ccache_version)"
    $identity["ccache_key"] = $identityBase
    $identity["ccache_restore_prefix"] = "$identityBase-"
    $identity["deps_key"] = "deps-archives-v$CcacheSchema-win-x64-lock$lockSha-schema$CcacheSchema"
    $identity["qt_cache_prefix"] = "qt-v$CcacheSchema-win-x64-qt$($identity.qt)-modules$moduleToken"
    $runId = Get-EnvOrNull "GITHUB_RUN_ID"
    $runAttempt = Get-EnvOrNull "GITHUB_RUN_ATTEMPT"
    if ($runId -and $runAttempt) {
        $identity["save_suffix"] = "$runId-$runAttempt"
        $identity["ccache_save_key"] = "$identityBase-$runId-$runAttempt"
        $identity["deps_save_key"] = "$($identity['deps_key'])-$runId-$runAttempt"
    } else {
        $identity["save_suffix"] = ""
        $identity["ccache_save_key"] = ""
        $identity["deps_save_key"] = ""
    }
    return $identity
}

function Get-CompilerCacheLaunchers {
    param([Parameter(Mandatory = $true)][string] $BuildDirectory)

    $pattern = '(^|\s|[\\/]|["\x27])(ccache|sccache|buildcache)(\.exe)?["\x27]?(?=\s|$)'
    $found = @()
    foreach ($relative in @("build.ninja", "rules.ninja", "CMakeFiles\rules.ninja")) {
        $file = Join-Path $BuildDirectory $relative
        if ((Test-Path -LiteralPath $file) -and (Select-String -LiteralPath $file -Pattern $pattern -Quiet)) {
            $found += $relative
        }
    }

    return $found
}

function Assert-InstallLayout {
    param(
        [Parameter(Mandatory = $true)][string] $InstallDirectory,
        [Parameter(Mandatory = $true)][string] $ExecutableRelative
    )

    if (-not (Test-Path -LiteralPath (Join-Path $InstallDirectory $ExecutableRelative))) {
        $entries = @(Get-ChildItem -LiteralPath $InstallDirectory -Force -ErrorAction SilentlyContinue | Select-Object -First 20 -ExpandProperty Name)
        throw "The expected executable '$ExecutableRelative' is missing from '$InstallDirectory' (contents: $($entries -join ', '))."
    }

    $installPrefixLength = (Get-FullPath $InstallDirectory).TrimEnd('\', '/').Length + 1
    $relativePaths = @(Get-ChildItem -LiteralPath $InstallDirectory -Recurse -File -Force -ErrorAction SilentlyContinue |
        ForEach-Object { $_.FullName.Substring($installPrefixLength).Replace('\', '/') })

    # Translations, soundfont and Qt runtime must arrive through the install rules
    # (MUE_RUN_LRELEASE, MUE_INSTALL_SOUNDFONT, MUE_RUN_WINDEPLOYQT) rather than
    # being copied by hand at package time.
    $translations = @($relativePaths | Where-Object { $_ -like "locale/*.qm" })
    $qtRuntime = @($relativePaths | Where-Object { $_ -eq "Qt6Core.dll" -or $_ -like "*/Qt6Core.dll" })
    $platformPlugin = @($relativePaths | Where-Object { $_ -eq "qwindows.dll" -or $_ -like "*/qwindows.dll" })

    # License and notice files are installed from the source tree (application LICENSE.txt
    # and the framework's SetupLicenseNotices.cmake, which reads the pinned payload trees).
    # They are part of the package contract, so a missing notice fails the build here.
    $noticeFiles = @(
        "licenses/LICENSE.txt"
        "licenses/SOURCE-REFS.txt"
        "licenses/qt-libraries/qtbase/LICENSES/LGPL-3.0-only.txt"
        "licenses/qt-libraries/qtbase/LICENSES/GPL-3.0-only.txt"
        "licenses/qt-libraries/qtbase/LICENSES/Qt-GPL-exception-1.0.txt"
        "licenses/qt-libraries/qtbase/src/dbus/LICENSE.LIBDBUS-1.txt"
        "licenses/qt-libraries/qtbase/src/3rdparty/freetype/LICENSE.txt"
        "licenses/qt-libraries/qtbase/src/3rdparty/harfbuzz-ng/COPYING"
        "licenses/qt-libraries/qtbase/src/3rdparty/libpng/LICENSE"
        "licenses/qt-libraries/qtbase/src/3rdparty/zlib/LICENSE"
        "licenses/qt-libraries/qtdeclarative/src/3rdparty/yoga/LICENSE"
        "licenses/qt-libraries/qtsvg/src/svg/LICENSE.XSVG.txt"
        "licenses/qt-libraries/qttools/src/assistant/qlitehtml/src/3rdparty/litehtml/LICENSE"
        "licenses/qt-libraries/qttools/src/qdoc/catch/LICENSE.CATCH.txt"
        "licenses/qt-libraries/qt5compat/src/core5/codecs/LICENSE.QBIG5CODEC.txt"
        "licenses/qt-libraries/qtshadertools/src/3rdparty/glslang/LICENSE.txt"
        "licenses/qt-libraries/qtshadertools/src/3rdparty/SPIRV-Cross/LICENSE"
        "licenses/qt-libraries/qtnetworkauth/LICENSES/BSD-3-Clause.txt"
        "licenses/qt-libraries/qttranslations/LICENSES/GPL-3.0-only.txt"
        "licenses/qt-libraries/qtwebsockets/LICENSES/LGPL-3.0-only.txt"
        "licenses/qt-libraries/qtbase/src/3rdparty/pcre2/LICENCE.md"
        "licenses/qt-libraries/qtbase/src/3rdparty/libjpeg/COPYRIGHT.txt"
        "licenses/qt-libraries/qttools/src/assistant/qlitehtml/src/3rdparty/GUMBO-AUTHORS.txt"
        "licenses/fdk-aac/NOTICE"
        "licenses/asiosdk/LICENSE.txt"
        "licenses/asiosdk/common/LICENSE.txt"
        "licenses/asiosdk/Steinberg ASIO Licensing Agreement.pdf"
        "licenses/harfbuzz/COPYING"
        "licenses/harfbuzz/src/ms-use/COPYING"
        "licenses/kddockwidgets/LICENSE.txt"
        "licenses/kddockwidgets/LICENSE.GPL.txt"
        "licenses/kddockwidgets/LICENSES/GPL-2.0-only.txt"
        "licenses/kddockwidgets/LICENSES/GPL-3.0-only.txt"
        "licenses/vst3sdk/base/LICENSE.txt"
        "licenses/vst3sdk/pluginterfaces/LICENSE.txt"
        "licenses/vst3sdk/public.sdk/LICENSE.txt"
        "licenses/zlib/README"
        "licenses/libsndfile/COPYING"
        "licenses/openssl/LICENSE"
        "licenses/freetype/LICENSE.TXT"
        "licenses/fluidsynth/LICENSE"
        "licenses/lame/COPYING"
        "licenses/lame/LICENSE"
        "licenses/flac/COPYING.Xiph"
        "licenses/flac/COPYING.LGPL"
        "licenses/flac/COPYING.GPL"
        "licenses/flac/COPYING.FDL"
        "licenses/opus/COPYING"
        "licenses/libopusenc/COPYING"
        "licenses/stb-vorbis/stb_vorbis.c"
        "licenses/kors/kors_async/LICENSE"
        "licenses/utf8cpp/LICENSE"
        "licenses/pugixml/pugixml.hpp"
        "licenses/picojson/picojson.h"
        "licenses/liblouis/COPYING"
        "licenses/liblouis/COPYING.LESSER"
        "licenses/liblouis/License.md"
        "licenses/intervaltree/LICENSE"
        "licenses/dtl/COPYING"
        "licenses/beatroot/COPYING"
        "licenses/rtf2html/COPYING.LESSER"
        "licenses/fonts/bravura/OFL.txt"
        "licenses/freefont/COPYING"
        "licenses/freefont/README"
        "licenses/freefont/AUTHORS"
        "licenses/mnxdom/LICENSE"
        "licenses/libmei/internal/libmei.h"
        "licenses/libmei/thirdparty/libmei/attclasses.h"
    )


    # Every selected Qt module is copied beneath its own directory, together with
    # the attribution or canonical metadata files used to assemble its notices.
    $missing = @()
    $qtModules = @(
        'qtbase'
        'qtdeclarative'
        'qtsvg'
        'qttools'
        'qttranslations'
        'qt5compat'
        'qtnetworkauth'
        'qtshadertools'
        'qtwebsockets'
    )
    foreach ($qtModule in $qtModules) {
        $modulePrefix = "licenses/qt-libraries/$qtModule/"
        $moduleMetadata = @($relativePaths | Where-Object {
            $_ -like "$modulePrefix*qt_attribution.json" -or
            $_ -like "$modulePrefix*REUSE.toml" -or
            $_ -like "$modulePrefix*licenseRule.json"
        })
        if ($moduleMetadata.Count -lt 1) {
            $missing += "$modulePrefix (Qt module metadata install rule)"
        }
    }
    foreach ($notice in $noticeFiles) {
        if ($relativePaths -notcontains $notice) { $missing += "$notice (license install rule)" }
    }
    if ($translations.Count -lt 1) { $missing += "locale/*.qm (lrelease install rule)" }
    if ($relativePaths -notcontains "locale/languages.json") { $missing += "locale/languages.json" }
    if ($relativePaths -notcontains "sound/MS Basic.sf3") { $missing += "sound/MS Basic.sf3 (soundfont install rule)" }
    if ($qtRuntime.Count -lt 1) { $missing += "Qt6Core.dll (windeployqt)" }
    if ($platformPlugin.Count -lt 1) { $missing += "qwindows.dll (windeployqt)" }
    if ($missing.Count -gt 0) {
        throw "The install tree at '$InstallDirectory' is missing: $($missing -join ', '). The install rules did not produce a complete package input."
    }

    return [ordered]@{
        executable         = $ExecutableRelative
        licenses           = $noticeFiles.Count
        translations       = $translations.Count
        languages_metadata = "locale/languages.json"
        soundfont          = "sound/MS Basic.sf3"
        qt_runtime         = $qtRuntime[0]
        qt_platform_plugin = $platformPlugin[0]
    }
}

function Get-ApplicationMetadata {
    param([Parameter(Mandatory = $true)][string] $SourceDirectory)

    $versionFile = Join-Path $SourceDirectory "version.cmake"
    $content = Get-Content -LiteralPath $versionFile -Raw

    $nameMatch = [regex]::Match($content, 'set\(MUSE_APP_NAME_MACHINE_READABLE\s+"([^"]+)"\)')
    $majorMatch = [regex]::Match($content, 'set\(MUSE_APP_VERSION_MAJOR\s+"([^"]+)"\)')
    $minorMatch = [regex]::Match($content, 'set\(MUSE_APP_VERSION_MINOR\s+"([^"]+)"\)')
    $patchMatch = [regex]::Match($content, 'set\(MUSE_APP_VERSION_PATCH\s+"([^"]+)"\)')
    if (-not ($nameMatch.Success -and $majorMatch.Success -and $minorMatch.Success -and $patchMatch.Success)) {
        throw "Could not derive the application identity from '$versionFile'."
    }

    $major = $majorMatch.Groups[1].Value
    $executableName = $nameMatch.Groups[1].Value + $major
    $applicationVersion = "$major.$($minorMatch.Groups[1].Value).$($patchMatch.Groups[1].Value)"

    return @{
        ExecutableRelative = "bin/$executableName.exe"
        ApplicationVersion = $applicationVersion
    }
}

# ---------------------------------------------------------------------------
# Inputs and source identity
# ---------------------------------------------------------------------------

$SourceDirectory = Get-FullPath $SourceDirectory
$OutputDirectory = Get-FullPath $OutputDirectory
$ProvenancePath = Get-FullPath $ProvenancePath
if ($UseCache) {
    $CcacheDirectory = Get-FullPath $CcacheDirectory
    $expectedCcacheDirectory = Get-FullPath (Join-Path $OutputDirectory "ccache")
    if ($CcacheDirectory -ine $expectedCcacheDirectory) {
        throw "-CcacheDirectory '$CcacheDirectory' must be the helper-owned '$expectedCcacheDirectory'."
    }
}

if (-not (Test-Path -LiteralPath $SourceDirectory -PathType Container)) {
    throw "-SourceDirectory '$SourceDirectory' does not exist."
}
if (Test-PathInside -Parent $SourceDirectory -Child $OutputDirectory) {
    throw "-OutputDirectory '$OutputDirectory' must not be inside -SourceDirectory '$SourceDirectory'."
}
if (Test-PathInside -Parent $SourceDirectory -Child $ProvenancePath) {
    throw "-ProvenancePath '$ProvenancePath' must not be inside -SourceDirectory '$SourceDirectory'."
}
if ($OutputDirectory -ieq $SourceDirectory) {
    throw "-OutputDirectory must not be -SourceDirectory ('$SourceDirectory')."
}
if ($SourceSha -notmatch '^[0-9a-f]{40}$') {
    throw "-SourceSha must be the full 40-character application commit; received '$SourceSha'."
}
if ($BuildNumber -notmatch '^[0-9]{1,9}$' -or [int64]$BuildNumber -gt $Int32Max) {
    throw "-BuildNumber must be a run number of at most 9 digits (Int32 limit for packaging); received '$BuildNumber'."
}

$DriverPath = Join-Path $SourceDirectory "ninja_build.ps1"
foreach ($required in @("CMakeLists.txt", "version.cmake", "ninja_build.ps1")) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $required) -PathType Leaf)) {
        throw "-SourceDirectory '$SourceDirectory' is missing '$required'; it is not a MuseScore application checkout."
    }
}

$InstallDirectory = Join-Path $OutputDirectory "install"
$LogDirectory = Join-Path $OutputDirectory "logs"
$BuildDirectory = Join-Path $SourceDirectory "build.release"
$CachePath = Join-Path $BuildDirectory "CMakeCache.txt"
$DriverLogPath = Join-Path $LogDirectory "ninja-build.log"

Write-Step "Validating source identity"
$null = Resolve-Tool -Name "git"
if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory ".git"))) {
    throw "-SourceDirectory '$SourceDirectory' is not a git checkout; an authoritative revision cannot be recorded."
}

$headSha = (Invoke-Tool -FilePath "git" -Arguments @("-C", $SourceDirectory, "rev-parse", "HEAD") -Purpose "git rev-parse HEAD").Trim()
if ($headSha -ne $SourceSha) {
    throw "-SourceSha '$SourceSha' does not match the checked out commit '$headSha' in '$SourceDirectory'."
}

$sourceStatus = Invoke-Tool -FilePath "git" -Arguments @("-C", $SourceDirectory, "status", "--porcelain", "--untracked-files=no", "--ignore-submodules=all") -Purpose "git status"
if ($sourceStatus -ne "") {
    throw "The application checkout at '$SourceDirectory' has uncommitted tracked changes; refusing to label the build with commit '$headSha':`n$sourceStatus"
}

$frameworkPath = Join-Path $SourceDirectory "muse"
if (-not (Test-Path -LiteralPath (Join-Path $frameworkPath ".git"))) {
    throw "The muse framework submodule is not checked out at '$frameworkPath'."
}

$frameworkSha = (Invoke-Tool -FilePath "git" -Arguments @("-C", $frameworkPath, "rev-parse", "HEAD") -Purpose "git rev-parse HEAD (framework)").Trim()
$frameworkStatus = Invoke-Tool -FilePath "git" -Arguments @("-C", $frameworkPath, "status", "--porcelain", "--untracked-files=no") -Purpose "git status (framework)"
if ($frameworkStatus -ne "") {
    throw "The framework checkout at '$frameworkPath' has uncommitted tracked changes; commit and push the framework repair instead of patching the worktree:`n$frameworkStatus"
}

$frameworkUrl = Invoke-Tool -FilePath "git" -Arguments @("-C", $SourceDirectory, "config", "-f", ".gitmodules", "submodule.muse_framework.url") -Purpose "framework URL"
$preflight = Get-Content -LiteralPath $ProvenancePath -Raw | ConvertFrom-Json -AsHashtable
$resolvedPreflight = @{
    source_sha = $headSha
    framework_sha = $frameworkSha
    framework_url = $frameworkUrl
    workflow_sha = $env:WORKFLOW_SHA
}
foreach ($entry in $resolvedPreflight.GetEnumerator()) {
    if (-not $entry.Value -or $preflight[$entry.Key] -cne $entry.Value) {
        throw "Preflight identity mismatch: $($entry.Key)"
    }
}
$dependencyLockRelative = "buildscripts/cmake/deps/dependencies.lock.cmake"
$dependencyLockPath = Join-Path $frameworkPath $dependencyLockRelative
if (-not (Test-Path -LiteralPath $dependencyLockPath -PathType Leaf)) {
    throw "The committed framework dependency lock is missing: $dependencyLockRelative"
}

$revision = $headSha.Substring(0, 7)
$application = Get-ApplicationMetadata -SourceDirectory $SourceDirectory

Write-Host "application sha : $headSha (revision $revision)"
Write-Host "framework sha   : $frameworkSha ($frameworkUrl)"
Write-Host "build number    : $BuildNumber, channel $Channel, $BuildType, $Architecture"

# The fork builds the soundfont committed in the source tree: the upstream
# DownloadSoundFont.cmake step is a mutable S3 auto-refresh that rewrites tracked
# files (share/sound/SF_VERSION and the payload), so it stays off and a missing
# committed payload must fail here instead of being fetched mid-build.
$soundfontRelative = "share/sound/MS Basic.sf3"
$soundfontLicenseRelative = "share/sound/MS Basic_License.md"
$soundfontVersionRelative = "share/sound/SF_VERSION"
foreach ($relative in @($soundfontRelative, $soundfontLicenseRelative, $soundfontVersionRelative)) {
    if (-not (Test-Path -LiteralPath (Join-Path $SourceDirectory $relative) -PathType Leaf)) {
        throw "The committed soundfont payload '$relative' is missing from '$SourceDirectory'; MUSESCORE_DOWNLOAD_SOUNDFONT is OFF, so the build cannot refresh it."
    }
}

$soundfont = [ordered]@{
    mode     = "source-pinned"
    file     = $soundfontRelative
    license  = $soundfontLicenseRelative
    version  = "$(Get-Content -LiteralPath (Join-Path $SourceDirectory $soundfontVersionRelative) -Raw)".Trim()
    sha256   = (Get-FileHash -LiteralPath (Join-Path $SourceDirectory $soundfontRelative) -Algorithm SHA256).Hash
    download = $false
}
Write-Host "soundfont     : $soundfontRelative (version $($soundfont['version']), sha256 $($soundfont['sha256']))"

if (Test-Path -LiteralPath $CachePath) {
    throw "A configured build tree already exists at '$CachePath'; the build must start from a fresh checkout."
}
if (Test-Path -LiteralPath $InstallDirectory) {
    $existing = @(Get-ChildItem -LiteralPath $InstallDirectory -Force)
    if ($existing.Count -gt 0) {
        throw "The install staging directory '$InstallDirectory' is not empty; use a fresh -OutputDirectory."
    }
}

# ---------------------------------------------------------------------------
# Toolchain
# ---------------------------------------------------------------------------

Write-Step "Selecting the MSVC toolchain"
$vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
if (-not (Test-Path -LiteralPath $vswhere)) {
    throw "vswhere.exe was not found; Visual Studio with the x64 C++ tools is required."
}

$vsJson = Invoke-Tool -FilePath $vswhere -Arguments @(
    "-latest", "-products", "*",
    "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
    "-format", "json") -Purpose "vswhere"
$instances = @($vsJson | ConvertFrom-Json)
if ($instances.Count -eq 0) {
    throw "vswhere found no Visual Studio instance with the x64 C++ tools (Microsoft.VisualStudio.Component.VC.Tools.x86.x64)."
}

$visualStudio = @{
    InstallationPath    = "$($instances[0].installationPath)"
    InstallationVersion = "$($instances[0].installationVersion)"
    DisplayName         = "$($instances[0].displayName)"
}
Write-Host "Visual Studio: $($visualStudio.DisplayName) $($visualStudio.InstallationVersion)"
Write-Host "  path        : $($visualStudio.InstallationPath)"
Import-MsvcEnvironment -InstallationPath $visualStudio.InstallationPath

if ($env:VSCMD_ARG_TGT_ARCH -ne "x64") {
    throw "Expected an x64 MSVC environment, got VSCMD_ARG_TGT_ARCH='$($env:VSCMD_ARG_TGT_ARCH)'."
}

$clPath = Resolve-Tool -Name "cl.exe"
$clVersion = Get-MsvcCompilerVersion -FilePath $clPath
Write-Host "cl.exe: $clPath ($clVersion, VCToolsVersion $($env:VCToolsVersion))"

$cmakePath = Resolve-Tool -Name "cmake"
$cmakeVersion = Get-ReportedVersion -FilePath $cmakePath -VersionArguments @("--version")
$ninjaPath = Resolve-Tool -Name "ninja"
$ninjaVersion = Get-ReportedVersion -FilePath $ninjaPath -VersionArguments @("--version")
Write-Host "cmake: $cmakePath ($cmakeVersion)"
Write-Host "ninja: $ninjaPath ($ninjaVersion)"

Write-Step "Resolving Qt"
$qtRoot = Resolve-QtRoot
foreach ($qtTool in @("qmake.exe", "windeployqt.exe", "lrelease.exe")) {
    if (-not (Test-Path -LiteralPath (Join-Path $qtRoot "bin\$qtTool"))) {
        throw "Qt tool '$qtTool' was not found in '$qtRoot\bin'; Qt 6 with deployment and linguist tools is required."
    }
}

# The installed CLI is the authoritative, version-format-independent source: Qt 6.10 moved
# PACKAGE_VERSION out of Qt6ConfigVersion.cmake into a separate included file, so the generated
# CMake files are no longer parsed here.
$qtVersion = Get-ReportedVersion -FilePath (Join-Path $qtRoot "bin\qmake.exe") -VersionArguments @("-query", "QT_VERSION")
if (-not $qtVersion) {
    throw "qmake -query QT_VERSION reported no version from '$qtRoot\bin\qmake.exe'."
}

# CMake finds Qt through CMAKE_PREFIX_PATH; the driver stays free of Qt flags.
$env:CMAKE_PREFIX_PATH = if ($env:CMAKE_PREFIX_PATH) { "$qtRoot;$env:CMAKE_PREFIX_PATH" } else { $qtRoot }
$env:PATH = (Join-Path $qtRoot "bin") + ";" + $env:PATH
Write-Host "Qt: $qtRoot ($qtVersion)"

# ---------------------------------------------------------------------------
# Build recipe
# ---------------------------------------------------------------------------

Write-Step "Configuring the build environment"
$cacheMode = if ($UseCache) { "ON" } else { "OFF" }
$buildEnvironment = [ordered]@{
    MUSESCORE_BUILD_CONFIGURATION             = "app"
    MUSE_APP_BUILD_MODE                       = $Channel
    MUSESCORE_BUILD_NUMBER                    = $BuildNumber
    MUSESCORE_REVISION                        = $revision
    MUSESCORE_INSTALL_DIR                     = $InstallDirectory
    MUSE_APP_INSTALL_SUFFIX                   = ""
    MUSESCORE_RUN_LRELEASE                    = "ON"
    # Soundfont is the source-pinned payload; the network auto-refresh would
    # rewrite tracked resources. The install rule (MUE_INSTALL_SOUNDFONT) stays on.
    MUSESCORE_DOWNLOAD_SOUNDFONT              = "OFF"
    MUSESCORE_BUILD_CRASHPAD_CLIENT           = "OFF"
    MUSESCORE_CRASHREPORT_URL                 = ""
    MUSESCORE_MODULE_UPDATE                   = "OFF"
    MUSESCORE_BUILD_UNIT_TESTS                = "OFF"
    MUSESCORE_UNIT_TESTS_ENABLE_CODE_COVERAGE = "OFF"
    MUSESCORE_BUILD_VST_MODULE                = "ON"
    MUSESCORE_BUILD_WEBSOCKET                 = "ON"
    MUSE_MODULE_AUDIO_EXPORT                  = "ON"
    MUSE_MODULE_AUDIO_ASIO                    = "ON"
    MUSESCORE_BUILD_PIPEWIRE_AUDIO_DRIVER     = "OFF"
    MUSESCORE_NO_RPATH                        = "OFF"
    MUSESCORE_COMPILE_USE_UNITY               = "ON"
    MUSE_COMPILE_USE_PCH                      = "ON"
    MUSESCORE_MSVC_DEBUG_FORMAT               = "Embedded"
    MUSESCORE_USE_CCACHE                      = $cacheMode
    MUSE_COMPILE_USE_COMPILER_CACHE           = $cacheMode
}

foreach ($entry in $buildEnvironment.GetEnumerator()) {
    [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
    Write-Host ("{0,-41}= '{1}'" -f $entry.Key, $entry.Value)
}

if ($UseCache) {
    $ccachePath = Assert-Ccache -Directory $CcacheDirectory
    foreach ($entry in ([ordered]@{
        CCACHE_DIR        = $CcacheDirectory
        CCACHE_MAXSIZE    = $CcacheMaxSize
        CCACHE_BASEDIR    = $SourceDirectory
        CCACHE_CPP2       = "true"
        CCACHE_SLOPPINESS = "pch_defines,time_macros"
    }).GetEnumerator()) {
        [Environment]::SetEnvironmentVariable($entry.Key, $entry.Value)
    }
    $null = Invoke-Tool -FilePath $ccachePath -Arguments @("--max-size=$CcacheMaxSize") -Purpose "ccache cache-size configuration"
    Write-Host "CCACHE_DIR       = '$CcacheDirectory'"
    Write-Host "CCACHE_MAXSIZE   = '$CcacheMaxSize'"
    Write-Host "CCACHE_BASEDIR   = '$SourceDirectory'"
    Write-Host "CCACHE_CPP2      = 'true'"
    Write-Host "CCACHE_SLOPPINESS= 'pch_defines,time_macros'"
} else {
    foreach ($name in @("CCACHE_DIR", "CCACHE_MAXSIZE", "CCACHE_BASEDIR", "CCACHE_CPP2", "CCACHE_SLOPPINESS")) {
        [Environment]::SetEnvironmentVariable($name, $null)
    }
}

# Only compile-affecting settings belong in the compiler-cache namespace. Run
# identity, build number, install paths and other provenance are intentionally
# excluded so compatible runs can share objects.
$cacheFlags = [ordered]@{
    build_type                              = $BuildType
    MUSESCORE_BUILD_CONFIGURATION           = $buildEnvironment.MUSESCORE_BUILD_CONFIGURATION
    MUSE_APP_BUILD_MODE                     = $buildEnvironment.MUSE_APP_BUILD_MODE
    MUSESCORE_BUILD_CRASHPAD_CLIENT         = $buildEnvironment.MUSESCORE_BUILD_CRASHPAD_CLIENT
    MUSESCORE_CRASHREPORT_URL               = $buildEnvironment.MUSESCORE_CRASHREPORT_URL
    MUSESCORE_MODULE_UPDATE                 = $buildEnvironment.MUSESCORE_MODULE_UPDATE
    MUSESCORE_BUILD_UNIT_TESTS              = $buildEnvironment.MUSESCORE_BUILD_UNIT_TESTS
    MUSESCORE_UNIT_TESTS_ENABLE_CODE_COVERAGE = $buildEnvironment.MUSESCORE_UNIT_TESTS_ENABLE_CODE_COVERAGE
    MUSESCORE_BUILD_VST_MODULE              = $buildEnvironment.MUSESCORE_BUILD_VST_MODULE
    MUSESCORE_BUILD_WEBSOCKET               = $buildEnvironment.MUSESCORE_BUILD_WEBSOCKET
    MUSE_MODULE_AUDIO_EXPORT                = $buildEnvironment.MUSE_MODULE_AUDIO_EXPORT
    MUSE_MODULE_AUDIO_ASIO                  = $buildEnvironment.MUSE_MODULE_AUDIO_ASIO
    MUSESCORE_NO_RPATH                        = $buildEnvironment.MUSESCORE_NO_RPATH
    MUSESCORE_COMPILE_USE_UNITY               = $buildEnvironment.MUSESCORE_COMPILE_USE_UNITY
    MUSE_COMPILE_USE_PCH                      = $buildEnvironment.MUSE_COMPILE_USE_PCH
    MUSESCORE_MSVC_DEBUG_FORMAT             = $buildEnvironment.MUSESCORE_MSVC_DEBUG_FORMAT
    MUSESCORE_USE_CCACHE                    = $buildEnvironment.MUSESCORE_USE_CCACHE
    MUSE_COMPILE_USE_COMPILER_CACHE         = $buildEnvironment.MUSE_COMPILE_USE_COMPILER_CACHE
}

$cacheIdentity = if ($UseCache) { Get-CacheIdentity } else { [ordered]@{} }
if ($CacheIdentityOnly) {
    if (-not $UseCache) {
        throw "-CacheIdentityOnly requires -UseCache so the identity describes the actual ccache toolchain."
    }
    Write-Output ($cacheIdentity | ConvertTo-Json -Compress)
    exit 0
}

New-Item -ItemType Directory -Force -Path $LogDirectory | Out-Null

# Record the host resources next to the build log, so a capacity-related failure can be
# diagnosed from the uploaded diagnostics instead of the (eventually expiring) run log.
$hostResources = @(
    "logical_processors: $([Environment]::ProcessorCount)"
    "chosen_jobs: $Jobs"
    "process_working_set_bytes: $([System.Diagnostics.Process]::GetCurrentProcess().WorkingSet64)"
    "runner_image: $($env:ImageOS) $($env:ImageVersion)"
)
try {
    $computerSystem = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
    $hostResources += "total_physical_memory_bytes: $($computerSystem.TotalPhysicalMemory)"
} catch {
    $hostResources += "total_physical_memory_bytes: unavailable ($($_.Exception.Message))"
}
try {
    $drive = Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Root -ieq [IO.Path]::GetPathRoot($OutputDirectory) } | Select-Object -First 1
    if ($drive) {
        $hostResources += "output_drive: $($drive.Root)"
        $hostResources += "output_drive_free_bytes: $($drive.Free)"
    } else {
        $hostResources += "output_drive_free_bytes: unknown"
    }
} catch {
    $hostResources += "resource probe failed: $_"
}
$hostResourcesText = $hostResources -join "`n"
Write-Host "Host: $($hostResourcesText -replace "`n", '; ')"
$hostResourcesPath = Join-Path $LogDirectory "host-resources.log"
[IO.File]::WriteAllText($hostResourcesPath, $hostResourcesText + "`n", (New-Object System.Text.UTF8Encoding($false)))

Write-Step "Building and installing ($DriverTarget, $Jobs jobs)"
$driverHost = Join-Path $PSHOME "pwsh.exe"
if (-not (Test-Path -LiteralPath $driverHost)) {
    $driverHost = Resolve-Tool -Name "pwsh"
}
$driverArguments = @("-NoProfile", "-NonInteractive")
if ($env:OS -eq "Windows_NT") {
    $driverArguments += @("-ExecutionPolicy", "Bypass")
}
$driverArguments += @("-File", $DriverPath, "-t", $DriverTarget, "-j", "$Jobs")

$driverCommand = "> $driverHost $($driverArguments -join ' ')"
Write-Host $driverCommand
$driverExitCode = 1
$buildStopwatch = [Diagnostics.Stopwatch]::StartNew()
try {
    if ($UseCache) {
        $ccacheStatsSummary["before"] = Write-CcacheStats -Phase "before"
    }
    Push-Location $SourceDirectory
    try {
        & $driverHost @driverArguments 2>&1 | Tee-Object -FilePath $DriverLogPath
        $driverExitCode = $LASTEXITCODE
    } finally {
        Pop-Location
    }
} finally {
    $buildStopwatch.Stop()
    if ($UseCache) {
        $ccacheStatsSummary["after"] = Write-CcacheStats -Phase "after"
        $ccacheStatsSummary["build_elapsed_seconds"] = [math]::Round($buildStopwatch.Elapsed.TotalSeconds, 3)
    }
}
if ($driverExitCode -ne 0) {
    throw "The build driver failed with exit code $driverExitCode. Command: $driverCommand. Log: $DriverLogPath"
}
$driverCommands = @(Select-String -LiteralPath $DriverLogPath -Pattern '^\s*>\s' | ForEach-Object { $_.Line.Trim() })

# ---------------------------------------------------------------------------
# Verify what was configured and installed
# ---------------------------------------------------------------------------

Write-Step "Verifying build metadata"
$cache = Get-CMakeCacheValues -CachePath $CachePath

$expectedValues = [ordered]@{
    CMAKE_BUILD_TYPE          = $BuildType
    MUSESCORE_BUILD_CONFIGURATION = "app"
    MUSE_APP_BUILD_MODE       = $Channel
    CMAKE_BUILD_NUMBER        = $BuildNumber
    MUSESCORE_REVISION        = $revision
}
$expectedOn = @(
    "MUE_RUN_LRELEASE",            # translations
    "MUE_INSTALL_SOUNDFONT",       # install rule for the committed soundfont
    "MUE_RUN_WINDEPLOYQT",         # Qt runtime deployment
    "MUSE_MODULE_AUDIO",
    "MUSE_MODULE_AUDIO_EXPORT",
    "MUSE_MODULE_AUDIO_ASIO",
    "MUSE_MODULE_VST",
    "MUSE_MODULE_NETWORK_WEBSOCKET",
    "MUSE_MODULE_ACCESSIBILITY",
    "MUE_BUILD_BRAILLE_MODULE",
    "MUSE_COMPILE_USE_UNITY",
    "MUSE_COMPILE_USE_PCH"
)
$expectedOff = @(
    "MUE_DOWNLOAD_SOUNDFONT",                    # source-pinned soundfont, no network refresh
    "MUSE_MODULE_DIAGNOSTICS_CRASHPAD_CLIENT",   # no crash upload
    "MUSE_MODULE_UPDATE",                        # no upstream update delivery
    "MUSE_ENABLE_UNIT_TESTS",
    "MUSE_ENABLE_UNIT_TESTS_CODE_COVERAGE"
)

$features = [ordered]@{}
foreach ($key in $expectedValues.Keys) {
    $features[$key] = Assert-CacheValue -Cache $cache -Key $key -Expected $expectedValues[$key]
}
foreach ($key in $expectedOn) {
    $features[$key] = Assert-CacheValue -Cache $cache -Key $key -Expected "ON"
}
foreach ($key in $expectedOff) {
    $features[$key] = Assert-CacheValue -Cache $cache -Key $key -Expected "OFF"
}
$expectedCacheMode = if ($UseCache) { "ON" } else { "OFF" }
$features["MUSE_COMPILE_USE_COMPILER_CACHE"] = Assert-CacheValue -Cache $cache -Key "MUSE_COMPILE_USE_COMPILER_CACHE" -Expected $expectedCacheMode

$cacheLaunchers = @(Get-CompilerCacheLaunchers -BuildDirectory $BuildDirectory)
if ($UseCache) {
    if ($cacheLaunchers.Count -eq 0) {
        throw "Compiler caching was enabled but no ccache launcher was present in the generated Ninja files."
    }
    foreach ($relative in $cacheLaunchers) {
        $file = Join-Path $BuildDirectory $relative
        if (-not (Select-String -LiteralPath $file -Pattern 'ccache(\.exe)?' -Quiet)) {
            throw "The generated Ninja file '$relative' uses a compiler cache other than the pinned ccache."
        }
    }
    foreach ($launcherKey in @("CMAKE_C_COMPILER_LAUNCHER", "CMAKE_CXX_COMPILER_LAUNCHER")) {
        if (-not $cache.ContainsKey($launcherKey) -or $cache[$launcherKey] -notmatch '(?i)(^|[\\/])ccache(\.exe)?$') {
            throw "CMakeCache entry '$launcherKey' does not point to the pinned ccache launcher."
        }
    }
} else {
    if ($cacheLaunchers.Count -gt 0) {
        throw "A compiler cache launcher is present in the generated Ninja files ($($cacheLaunchers -join ', ')) although MUSESCORE_USE_CCACHE=OFF."
    }
    foreach ($launcherKey in @("CMAKE_C_COMPILER_LAUNCHER", "CMAKE_CXX_COMPILER_LAUNCHER")) {
        if ($cache.ContainsKey($launcherKey) -and $cache[$launcherKey]) {
            throw "CMakeCache entry '$launcherKey' is '$($cache[$launcherKey])' although the compiler cache is disabled."
        }
    }
}
$features.GetEnumerator() | ForEach-Object { Write-Host ("{0,-41}= {1}" -f $_.Key, $(if ($null -eq $_.Value) { "<absent>" } else { $_.Value })) }
if ($UseCache) {
    Write-Host "compiler cache launchers in Ninja files: $($cacheLaunchers -join ', ')"
} else {
    Write-Host "compiler cache launchers in Ninja files: none"
}

Write-Step "Verifying the install tree"
$resources = Assert-InstallLayout -InstallDirectory $InstallDirectory -ExecutableRelative $application.ExecutableRelative
$resources.GetEnumerator() | ForEach-Object { Write-Host ("{0,-19}: {1}" -f $_.Key, $_.Value) }

# ---------------------------------------------------------------------------
# Provenance for the packaging helper
# ---------------------------------------------------------------------------

$driverFile = Get-Item -LiteralPath $DriverPath
$compilerCache = [ordered]@{
    enabled                         = [bool]$UseCache
    effective_use_cache             = [bool]$UseCache
    directory                       = if ($UseCache) { $CcacheDirectory } else { $null }
    max_size                        = if ($UseCache) { $CcacheMaxSize } else { $null }
    version                         = if ($UseCache) { $DetectedCcacheVersion } else { $null }
    identity                        = $cacheIdentity
    ccache_cache_matched_key        = Get-EnvOrNull "CCACHE_CACHE_MATCHED_KEY"
    dependency_cache_matched_key    = Get-EnvOrNull "DEPS_CACHE_MATCHED_KEY"
    qt_cache_key_prefix             = if (Get-EnvOrNull "QT_CACHE_KEY_PREFIX") { Get-EnvOrNull "QT_CACHE_KEY_PREFIX" } elseif ($UseCache) { $cacheIdentity["qt_cache_prefix"] } else { $null }
    stats                           = $ccacheStatsSummary
    launchers_in_ninja_files        = $cacheLaunchers
}
$resolvedIdentity = [ordered]@{
    repository           = (Get-EnvOrNull "GITHUB_REPOSITORY")
    requested_source_ref = $SourceRef
    source_sha           = $headSha
    source_revision      = $revision
    framework_url        = $frameworkUrl
    framework_sha        = $frameworkSha
    workflow_sha         = (Get-EnvOrNull "WORKFLOW_SHA")
    run_id               = (Get-EnvOrNull "GITHUB_RUN_ID")
    run_attempt          = (Get-EnvOrNull "GITHUB_RUN_ATTEMPT")
}
$buildValues = [ordered]@{
    application_version      = $application.ApplicationVersion
    application_version_full = "$($application.ApplicationVersion).$BuildNumber"
    executable               = $application.ExecutableRelative
    channel                  = $Channel
    architecture             = $Architecture
    build_type               = $BuildType
    features                 = $features
    compiler_cache           = $compilerCache
    toolchain                = [ordered]@{
        visual_studio = $visualStudio
        msvc          = [ordered]@{ compiler_path = $clPath; compiler_version = "$clVersion"; tools_version = "$($env:VCToolsVersion)" }
        windows_sdk   = [ordered]@{ version = "$($env:WindowsSDKVersion)".TrimEnd('\'); directory = "$($env:WindowsSdkDir)" }
        cmake         = [ordered]@{ path = $cmakePath; version = $cmakeVersion }
        ninja         = [ordered]@{ path = $ninjaPath; version = $ninjaVersion }
        python        = Get-ReportedVersion -FilePath (Resolve-Tool -Name "python") -VersionArguments @("--version")
        runner_image  = [ordered]@{ os = $env:ImageOS; version = $env:ImageVersion }
        qt            = [ordered]@{ root = $qtRoot; version = $qtVersion }
    }
    dependency_lock          = [ordered]@{
        framework_sha = $frameworkSha
        lock_file = $dependencyLockRelative
        sha256 = (Get-FileHash -LiteralPath $dependencyLockPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    soundfont                = $soundfont
    install                  = [ordered]@{ directory = $InstallDirectory; resources = $resources }
    build                    = [ordered]@{
        driver            = $DriverPath
        driver_sha256     = (Get-FileHash -LiteralPath $DriverPath -Algorithm SHA256).Hash
        driver_last_write = $driverFile.LastWriteTimeUtc.ToString("yyyy-MM-ddTHH:mm:ssZ")
        target            = $DriverTarget
        jobs              = $Jobs
        command           = $driverCommand
        commands          = $driverCommands
        log               = $DriverLogPath
        environment       = $buildEnvironment
    }
    build_provenance_schema  = "fork-windows-build-provenance/v1"
    generated_utc            = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# A preflight step may have written the shared document already; keep its keys
# and fail on contradictions instead of silently relabelling the run.
$document = [ordered]@{}
if (Test-Path -LiteralPath $ProvenancePath) {
    $rawProvenance = Get-Content -LiteralPath $ProvenancePath -Raw
    if (-not [string]::IsNullOrWhiteSpace($rawProvenance)) {
        $existing = $rawProvenance | ConvertFrom-Json -AsHashtable
        if (-not ($existing -is [System.Collections.IDictionary])) {
            throw "The provenance document at '$ProvenancePath' does not contain a JSON object."
        }
        foreach ($key in $existing.Keys) {
            $document[$key] = $existing[$key]
        }
    }
}
foreach ($key in $resolvedIdentity.Keys) {
    $value = $resolvedIdentity[$key]
    if ($value -and $document.Contains($key) -and $document[$key] -and ("$($document[$key])" -ne "$value")) {
        throw "Provenance conflict for '$key': the existing document says '$($document[$key])' but this build resolved '$value'."
    }
    if (-not $document.Contains($key)) {
        # Written even when unresolved, so the packaging helper always finds the key.
        $document[$key] = $value
    }
}
foreach ($key in $buildValues.Keys) {
    $document[$key] = $buildValues[$key]
}
if (-not $document.Contains("schema")) {
    $document["schema"] = "fork-windows-provenance/v1"
}

# package-windows.ps1 refuses a provenance file that lacks any of these, so fail
# here with the actual cause instead of during packaging.
$packageRequiredKeys = @(
    "repository", "requested_source_ref", "source_sha", "framework_url", "framework_sha", "workflow_sha",
    "run_id", "run_attempt", "application_version", "channel", "build_type", "features", "toolchain",
    "dependency_lock"
)
$unresolved = @($packageRequiredKeys | Where-Object { -not $document.Contains($_) })
if ($unresolved.Count -gt 0) {
    throw "Provenance identity is incomplete: $($unresolved -join ', '). Run inside GitHub Actions (GITHUB_REPOSITORY/GITHUB_SHA/GITHUB_RUN_ID/GITHUB_RUN_ATTEMPT), pass -SourceRef, or let preflight write these keys."
}

$provenanceParent = Split-Path -Parent $ProvenancePath
if ($provenanceParent -and -not (Test-Path -LiteralPath $provenanceParent)) {
    New-Item -ItemType Directory -Force -Path $provenanceParent | Out-Null
}
[IO.File]::WriteAllText($ProvenancePath, ($document | ConvertTo-Json -Depth 8) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))

Write-Step "Done"
Write-Host "install tree : $InstallDirectory"
Write-Host "executable   : $($application.ExecutableRelative)"
Write-Host "provenance   : $ProvenancePath"
Write-Host "build log    : $DriverLogPath"
