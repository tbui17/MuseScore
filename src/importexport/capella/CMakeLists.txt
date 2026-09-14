# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies
#
# MuseScore Studio
# Music Composition & Notation
#
# Copyright (C) 2026 MuseScore Limited and others
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
# along with this program. If not, see <https://www.gnu.org/licenses/>.

muse_create_module(iex_capella)

target_sources(iex_capella PRIVATE
    capellamodule.cpp
    capellamodule.h

    internal/capellareader.cpp
    internal/capellareader.h
    internal/capella.cpp
    internal/capella.h
    internal/capxml.cpp
)

add_subdirectory(thirdparty/rtf2html)

if (MUSE_APP_INSTALL_RESOURCES_LOCATION)
    include(SetupLicenseNotices)
    muse_install_license_notice(rtf2html "${CMAKE_CURRENT_LIST_DIR}/thirdparty/rtf2html" "COPYING.LESSER")
endif()

target_link_libraries(iex_capella PRIVATE
    rtf2html
    engraving
)

if (MUE_BUILD_IMPORTEXPORT_TESTS)
    add_subdirectory(tests)
endif()
