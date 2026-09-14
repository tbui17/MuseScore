# ![MuseScore Studio](share/icons/musescore_logo_full.png)

Music notation and composition software

[![License: GPL v3](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0.en.html)
[![Coverage](https://s3.us-east-1.amazonaws.com/extensions.musescore.org/test/code_coverage/coverage_badge.svg?)](https://github.com/musescore/MuseScore/actions/workflows/check_unit_tests.yml)

MuseScore Studio is an open source and free music notation software. For support, contribution, and bug reports visit MuseScore.org. Fork and make pull requests!

## Features

- WYSIWYG design, notes are entered on a "virtual notepaper"
- TrueType font(s) for printing & display allows for high quality scaling to all sizes
- Easy & fast note entry
- Many editing functions
- MusicXML import/export
- MIDI (SMF) import/export
- MEI import/export
- MuseData import
- MIDI input for note entry
- Integrated sequencer and software synthesizer to play the score
- Print or create PDF files

## More info

- [MuseScore Studio Homepage](https://musescore.org)
- [MuseScore Studio Git workflow instructions](https://musescore.org/en/developers-handbook/git-workflow)
- [How to compile MuseScore Studio?](https://github.com/musescore/MuseScore/wiki/Set-up-developer-environment)

## License

MuseScore Studio is licensed under GPL version 3.0. See [license file](https://github.com/musescore/MuseScore/blob/master/LICENSE.txt) in the same directory.

## Packages

See [Code Structure on Wiki](https://github.com/musescore/MuseScore/wiki/CodeStructure)

### Tested Windows candidate

The planned `fork-2026.09.14.1` release is an unsigned, extract-and-run development build. It is not an installer or a stable release. The pipeline creates the tag and draft prerelease once; this block never uses `latest` and refuses to reuse a download directory.

Run this after the draft release is published. It downloads exactly one ZIP, `build-manifest.json`, and `SHA256SUMS.txt` from that immutable tag, verifies the manifest and checksum before extraction, and then launches the extracted executable:

```powershell
$ErrorActionPreference = 'Stop'

$repo = 'tbui17/MuseScore'
$tag = 'fork-2026.09.14.1'
$downloadRoot = Join-Path ([Environment]::GetFolderPath('UserProfile')) "Downloads\MuseScore-$tag"

if (Test-Path -LiteralPath $downloadRoot) {
    throw "Refusing to reuse existing directory: $downloadRoot"
}
New-Item -ItemType Directory -Path $downloadRoot | Out-Null

$release = gh release view $tag --repo $repo --json tagName,isDraft,isPrerelease | ConvertFrom-Json
if ($LASTEXITCODE -ne 0 -or $release.tagName -cne $tag) {
    throw "Release tag '$tag' was not found in $repo."
}
if (-not $release.isDraft -or -not $release.isPrerelease) {
    throw "Expected the pipeline's draft prerelease for $tag."
}

gh release download $tag --repo $repo `
    --pattern '*.zip' `
    --pattern 'build-manifest.json' `
    --pattern 'SHA256SUMS.txt' `
    --dir $downloadRoot
if ($LASTEXITCODE -ne 0) {
    throw "GitHub CLI failed to download release assets."
}

$entries = @(Get-ChildItem -LiteralPath $downloadRoot -Force)
$files = @($entries | Where-Object { -not $_.PSIsContainer })
$zipFiles = @($files | Where-Object { $_.Name -match '\.zip$' })
if ($entries.Count -ne 3 -or $files.Count -ne 3 -or $zipFiles.Count -ne 1) {
    throw "Expected exactly three files: one ZIP, build-manifest.json, and SHA256SUMS.txt."
}

$manifestPath = Join-Path $downloadRoot 'build-manifest.json'
$checksumsPath = Join-Path $downloadRoot 'SHA256SUMS.txt'
$expectedNames = @($zipFiles[0].Name, 'build-manifest.json', 'SHA256SUMS.txt') | Sort-Object
$actualNames = @($files | ForEach-Object { $_.Name } | Sort-Object)
if (@(Compare-Object -ReferenceObject $expectedNames -DifferenceObject $actualNames).Count -ne 0) {
    throw "Downloaded assets are not exactly the expected package, manifest, and checksum files."
}

$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ([string]$manifest.repository -cne $repo) {
    throw "Manifest repository does not match $repo."
}
$package = $manifest.package
$packageName = [string]$package.filename
if ([string]::IsNullOrWhiteSpace($packageName) -or
    $packageName -notmatch '^[A-Za-z0-9][A-Za-z0-9._-]+\.zip$') {
    throw "Manifest contains an unsafe package filename."
}
if ($packageName -cne $zipFiles[0].Name) {
    throw "Manifest package name does not match the downloaded ZIP."
}

$packageSize = [int64]$package.size
$packageHash = ([string]$package.sha256).ToLowerInvariant()
$zipHash = (Get-FileHash -LiteralPath $zipFiles[0].FullName -Algorithm SHA256).Hash.ToLowerInvariant()
if ($packageSize -le 0 -or $packageSize -ne $zipFiles[0].Length -or $packageHash -ne $zipHash) {
    throw "Manifest package size or SHA-256 does not match the downloaded ZIP."
}
if ((Get-Content -LiteralPath $checksumsPath -Raw).Trim() -cne "$zipHash  $packageName") {
    throw "SHA256SUMS.txt does not identify the exact package bytes."
}

$extractRoot = Join-Path $downloadRoot 'MuseScore'
New-Item -ItemType Directory -Path $extractRoot | Out-Null
Expand-Archive -LiteralPath $zipFiles[0].FullName -DestinationPath $extractRoot

$relativeExecutable = [string]$manifest.executable
if ([string]::IsNullOrWhiteSpace($relativeExecutable) -or
    [IO.Path]::IsPathRooted($relativeExecutable) -or
    $relativeExecutable -match '(^|[\\/])\.\.([\\/]|$)') {
    throw "Manifest contains an unsafe executable path."
}
$executable = Join-Path $extractRoot ($relativeExecutable -replace '/', '\')
if (-not (Test-Path -LiteralPath $executable -PathType Leaf)) {
    throw "Manifest executable was not found after extraction: $relativeExecutable"
}

Write-Host "Unsigned development build extracted to $extractRoot"
Start-Process -FilePath $executable -WorkingDirectory (Split-Path -Parent $executable)
```


## Building

**Read the [Compilation section](https://github.com/musescore/MuseScore/wiki/Set-up-developer-environment) of the [MuseScore Wiki](https://github.com/musescore/MuseScore/wiki) for a complete build walkthrough and a list of dependencies.**

### Getting sources

If using git to download repo of entire code history, type:

    git clone https://github.com/musescore/MuseScore.git
    cd MuseScore

Otherwise, you can just download the latest source release tarball from the [Releases page](https://github.com/musescore/MuseScore/releases), and then from your download directory type:

    tar xzf MuseScore-x.x.x.tar.gz
    cd MuseScore-x.x.x

### Release Build

To compile MuseScore Studio for release, type:

    cmake -P build.cmake -DCMAKE_BUILD_TYPE=Release

If something goes wrong, append the word "clean" to the above command to delete the build subdirectory:

    cmake -P build.cmake -DCMAKE_BUILD_TYPE=Release clean

Then try running the first command again.

### Running

To start MuseScore Studio, type:

    cmake -P build.cmake -DCMAKE_BUILD_TYPE=Release run

Or run the compiled executable directly.

### Debug Build

A debug version can be built and run by replacing `-DCMAKE_BUILD_TYPE=Release`
with `-DCMAKE_BUILD_TYPE=Debug` in the above commands.

If you omit the `-DCMAKE_BUILD_TYPE` option entirely then `RelWithDebInfo` is
used by default, as it provides a useful compromise between Release and Debug.

### Testing

See the [Unit tests section](https://github.com/musescore/MuseScore/wiki/Unit-tests) of the [MuseScore Studio Wiki](https://github.com/musescore/MuseScore/wiki) for instructions on how to run the test suite.

### Code Formatting

Run `./hooks/install.sh` to install a pre-commit hook that will format your staged files. Requires that you install `uncrustify`.

If you have problems, please report them. To uninstall, run `./hooks/uninstall.sh`.
