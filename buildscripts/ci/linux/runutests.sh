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

set -Ee
trap 'echo Unit tests failed; exit 1' ERR

BUILD_TOOLS=$HOME/build_tools
ENVIRONMENT_FILE=$BUILD_TOOLS/environment.sh
if [ ! -f "$ENVIRONMENT_FILE" ]; then
    echo "Missing $ENVIRONMENT_FILE; the Linux setup step must run before the unit tests" >&2
    exit 1
fi
source "$ENVIRONMENT_FILE"

BUILD_DIR="build.debug"
if [ ! -d "$BUILD_DIR" ]; then
    echo "Missing $BUILD_DIR; the unit tests were not built" >&2
    exit 1
fi
cd "$BUILD_DIR"

export GTEST_OUTPUT=xml:test-results
export GTEST_COLOR=1

# run the tests in "minimal" platform for headless systems
# enable fonts handling
export QT_QPA_PLATFORM=minimal:enable_fonts

# if AddressSanitizer was used, disable leak detection
export ASAN_OPTIONS=detect_leaks=0:new_delete_type_mismatch=0

# --no-tests=error (CMake 3.20+) turns an empty test list into a failure, so a build that
# produced no unit tests can never satisfy the mandatory unit gate.
ctest --no-tests=error -V
