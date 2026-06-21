muse_create_module(braille)

add_subdirectory(tables)
add_subdirectory(thirdparty/liblouis)

target_sources(braille PRIVATE
    braillemodule.cpp
    braillemodule.h
    ibrailleconfiguration.h
    ibrailleconverter.h
    inotationbraille.h
    internal/braillecode.cpp
    internal/braillecode.h
    internal/brailleconfiguration.cpp
    internal/brailleconfiguration.h
    internal/brailleconverter.cpp
    internal/brailleconverter.h
    internal/brailleinput.cpp
    internal/brailleinput.h
    internal/brailleinputparser.cpp
    internal/brailleinputparser.h
    internal/braillewriter.cpp
    internal/braillewriter.h
    internal/braille.cpp
    internal/braille.h
    internal/louis.cpp
    internal/louis.h
    internal/notationbraille.cpp
    internal/notationbraille.h
)

target_link_libraries(braille PRIVATE
    engraving
    liblouis
)

if (OS_IS_WIN AND NOT CMAKE_GENERATOR MATCHES "Visual Studio")
    set(BRAILLE_TABLES_OUTPUT_DIR "${CMAKE_BINARY_DIR}/../tables")
    add_custom_command(TARGET braille POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/thirdparty/liblouis/tables"
            "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy_directory
            "${CMAKE_CURRENT_SOURCE_DIR}/tables"
            "${BRAILLE_TABLES_OUTPUT_DIR}"
        COMMENT "Copying braille tables to ${BRAILLE_TABLES_OUTPUT_DIR}"
    )
endif()

if (MUE_BUILD_BRAILLE_TESTS)
    add_subdirectory(tests)
endif()

if (MUE_BUILD_BRAILLE_QML)
    add_subdirectory(qml/MuseScore/Braille)
endif()
