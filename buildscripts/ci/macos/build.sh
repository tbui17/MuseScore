#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# MuseScore Studio
# Music Composition & Notation
#
# Copyright (C) 2021 MuseScore Limited and others
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License version 3 as
# published by the Free Software Foundation.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.
echo "Build MuseScore"
set -Ee
trap 'echo Build failed; exit 1' ERR

ARTIFACTS_DIR=build.artifacts
CRASH_REPORT_URL=""
BUILD_NUMBER=""
BUILD_CRASHPAD_CLIENT="OFF"

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -n|--number|--crash_log_url)
            if [ "$#" -lt 2 ] || [[ "$2" == -* ]]; then
                echo "error: missing value for $1" >&2
                exit 1
            fi
            ;;
    esac
    case $1 in
        -n|--number) BUILD_NUMBER="$2"; shift ;;
        --crash_log_url) CRASH_REPORT_URL="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Legacy workflows pass literal quote characters as the empty-URL sentinel.
# Quotes produced by variable expansion are data, not shell syntax. Derive the
# feature flag from the final value, so repeated options also obey last-value wins.
case "$CRASH_REPORT_URL" in
    ""|"''"|'""') CRASH_REPORT_URL=""; BUILD_CRASHPAD_CLIENT=OFF ;;
    *) BUILD_CRASHPAD_CLIENT=ON ;;
esac

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
    echo "error: BUILD_NUMBER must be a nonempty decimal number" >&2
    exit 1
fi

BUILD_MODE=$(cat "$ARTIFACTS_DIR/env/build_mode.env")
case "$BUILD_MODE" in
    devel|nightly) MUSE_APP_BUILD_MODE=dev ;;
    testing) MUSE_APP_BUILD_MODE=testing ;;
    stable) MUSE_APP_BUILD_MODE=release ;;
    *) echo "error: unknown BUILD_MODE" >&2; exit 1 ;;
esac

echo "MUSE_APP_BUILD_MODE: $MUSE_APP_BUILD_MODE"
echo "BUILD_NUMBER: $BUILD_NUMBER"
echo "BUILD_CRASHPAD_CLIENT: $BUILD_CRASHPAD_CLIENT"

MUSESCORE_REVISION=$(git rev-parse --short=7 HEAD)

MUSESCORE_MACOS_DEPS_PATH="$HOME/musescore_deps_macos" \
CMAKE_OSX_ARCHITECTURES="arm64;x86_64" \
MUSESCORE_INSTALL_DIR="../applebuild" \
MUSE_APP_BUILD_MODE=$MUSE_APP_BUILD_MODE \
MUSESCORE_BUILD_NUMBER=$BUILD_NUMBER \
MUSESCORE_REVISION=$MUSESCORE_REVISION \
MUSESCORE_CRASHREPORT_URL=$CRASH_REPORT_URL \
MUSESCORE_BUILD_CRASHPAD_CLIENT=$BUILD_CRASHPAD_CLIENT \
MUSESCORE_BUILD_VST_MODULE="ON" \
MUSESCORE_BUILD_WEBSOCKET="ON" \
bash ./ninja_build.sh -t install

bash ./buildscripts/ci/tools/make_release_channel_env.sh -c "$MUSE_APP_BUILD_MODE"
bash ./buildscripts/ci/tools/make_version_env.sh "$BUILD_NUMBER"
bash ./buildscripts/ci/tools/make_revision_env.sh "$MUSESCORE_REVISION"
bash ./buildscripts/ci/tools/make_branch_env.sh
