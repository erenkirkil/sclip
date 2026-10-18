cmake_minimum_required(VERSION 3.25)
project(sclip LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

enable_testing()

# Portable core: standard C++ only, never includes Windows headers.
add_library(sclip_core STATIC core/version.cpp)
target_include_directories(sclip_core PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})

add_executable(sclip_tests tests/smoke_test.cpp)
target_link_libraries(sclip_tests PRIVATE sclip_core)
add_test(NAME smoke COMMAND sclip_tests)

if(MSVC)
  foreach(tgt sclip_core sclip_tests)
    target_compile_options(${tgt} PRIVATE /W4 /WX /permissive- /utf-8)
  endforeach()
endif()

# Win32 tray application: only meaningful on Windows (built in Windows CI).
if(WIN32)
  add_executable(sclip WIN32
    app/main.cpp
    res/sclip.manifest)
  target_link_libraries(sclip PRIVATE sclip_core user32 shell32)
  target_compile_definitions(sclip PRIVATE
    UNICODE _UNICODE WIN32_LEAN_AND_MEAN NOMINMAX)
  if(MSVC)
    target_compile_options(sclip PRIVATE /W4 /WX /permissive- /utf-8)
  endif()
endif()
