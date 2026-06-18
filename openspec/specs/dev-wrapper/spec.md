# dev-wrapper Specification

## Purpose
Define the Windows daily-development wrapper for common MuseScore developer workflows.

## Requirements

### Requirement: Dev wrapper entry point
The repository SHALL provide a Windows `dev.ps1` entry point for daily development commands.

#### Scenario: User invokes dev wrapper
- **WHEN** a user runs `dev.ps1` from the repository root
- **THEN** the wrapper dispatches the requested daily development command

#### Scenario: No batch wrapper is required
- **WHEN** the change is implemented
- **THEN** the repository contains `dev.ps1` as the new wrapper and does not require a new `dev.bat` file

### Requirement: Help command
The dev wrapper SHALL show concise usage help when invoked with no command, `help`, `-h`, or `--help`.

#### Scenario: No command is provided
- **WHEN** a user runs `dev` with no arguments
- **THEN** the wrapper prints the supported commands `build`, `run`, `test`, and `clean`

#### Scenario: Help flag is provided
- **WHEN** a user runs `dev --help`
- **THEN** the wrapper prints usage help and exits successfully

### Requirement: Debug build command
The dev wrapper SHALL provide `dev build` for the default Debug build and SHALL delegate the actual build to the existing MuseScore build wrapper.

#### Scenario: User builds the Debug configuration
- **WHEN** a user runs `dev build`
- **THEN** the wrapper invokes the existing Debug build flow equivalent to `ninja_build.bat -t debug`

#### Scenario: User limits build parallelism
- **WHEN** a user runs `dev build -j 8`
- **THEN** the wrapper passes the job limit through to the underlying build command

#### Scenario: Build fails
- **WHEN** the underlying build command exits with a non-zero status
- **THEN** the dev wrapper exits with a non-zero status

### Requirement: Debug run command
The dev wrapper SHALL provide `dev run` to launch the Debug MuseScore executable directly from the Debug build tree without using `build.install`.

#### Scenario: Debug executable exists
- **WHEN** a user runs `dev run --debug`
- **THEN** the wrapper launches the Debug executable and forwards `--debug` to MuseScore

#### Scenario: Debug executable is missing
- **WHEN** a user runs `dev run` and the Debug executable does not exist
- **THEN** the wrapper prints the expected executable path and instructs the user to run `dev build`

#### Scenario: Run command fails
- **WHEN** the launched executable exits with a non-zero status
- **THEN** the dev wrapper exits with a non-zero status

### Requirement: App test-case command
The dev wrapper SHALL provide `dev test <script>` for running app-level MuseScore test-case scripts through the Debug executable.

#### Scenario: User runs a test-case script
- **WHEN** a user runs `dev test vtest\vtest.js`
- **THEN** the wrapper launches the Debug executable with `--test-case vtest\vtest.js`

#### Scenario: User passes additional test-case arguments
- **WHEN** a user runs `dev test vtest\vtest.js --test-case-context vtest\vtest_context.json`
- **THEN** the wrapper forwards `--test-case-context vtest\vtest_context.json` unchanged after the `--test-case` argument

#### Scenario: Test script is omitted
- **WHEN** a user runs `dev test` without a script path
- **THEN** the wrapper prints usage for the test command and exits with a non-zero status

### Requirement: Safe clean command
The dev wrapper SHALL provide `dev clean` for deleting local build output directories and SHALL perform a dry run unless `--yes` is supplied.

#### Scenario: User previews all clean targets
- **WHEN** a user runs `dev clean`
- **THEN** the wrapper lists the `build.debug`, `build.release`, and `build.install` directories that would be deleted without deleting them

#### Scenario: User confirms all clean targets
- **WHEN** a user runs `dev clean --yes`
- **THEN** the wrapper deletes existing `build.debug`, `build.release`, and `build.install` directories

#### Scenario: User previews one clean target
- **WHEN** a user runs `dev clean debug`
- **THEN** the wrapper lists only the `build.debug` directory without deleting it

#### Scenario: User confirms one clean target
- **WHEN** a user runs `dev clean install --yes`
- **THEN** the wrapper deletes `build.install` if it exists and does not delete `build.debug` or `build.release`

#### Scenario: User provides an unknown clean target
- **WHEN** a user runs `dev clean cache`
- **THEN** the wrapper prints clean command usage and exits with a non-zero status

### Requirement: Minimal v1 command surface
The dev wrapper SHALL NOT provide v1 commands for release builds, install builds, compile command generation, packaging, or full unit-test-suite execution.

#### Scenario: User requests an unsupported command
- **WHEN** a user runs `dev build-release`
- **THEN** the wrapper reports the command as unsupported and prints usage help

#### Scenario: User needs advanced build behavior
- **WHEN** a user needs release, install, compile-command, packaging, or full-suite behavior
- **THEN** the user uses the existing lower-level MuseScore build or test commands outside the v1 dev wrapper
