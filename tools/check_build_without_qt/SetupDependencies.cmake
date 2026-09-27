# SPDX-License-Identifier: GPL-3.0-only
# MuseScore-Studio-CLA-applies

include_guard(GLOBAL)

if(MUSE_QT_SUPPORT)
    message(FATAL_ERROR "The standalone dependency bootstrap is only for the no-Qt check")
endif()

# Reuse reviewed recipes and pinned payload verification, rather than relying on
# accidental host include paths or loading the full desktop/audio dependency set.
include("${MUSE_FRAMEWORK_PATH}/buildscripts/cmake/MuseDeps.cmake")
foreach(_dependency IN ITEMS picojson pugixml utfcpp)
    populate(${_dependency})
    if(NOT TARGET ${_dependency})
        message(FATAL_ERROR
            "No-Qt dependency bootstrap did not define required target: ${_dependency}")
    endif()
endforeach()
unset(_dependency)
