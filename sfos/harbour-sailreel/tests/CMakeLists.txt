cmake_minimum_required(VERSION 3.5)
project(test_ytdlptranslate CXX)

find_package(Qt5 COMPONENTS Core Test REQUIRED)

set(CMAKE_AUTOMOC ON)

add_executable(test_ytdlptranslate
    testytdlptranslate.cpp
    "${CMAKE_CURRENT_SOURCE_DIR}/../src/ytdlptranslate.cpp"
)
target_compile_definitions(test_ytdlptranslate PRIVATE
    TESTDATA_DIR="${CMAKE_CURRENT_SOURCE_DIR}"
)
target_link_libraries(test_ytdlptranslate
    Qt5::Core
    Qt5::Test
)
add_test(NAME ytdlptranslate COMMAND test_ytdlptranslate)
