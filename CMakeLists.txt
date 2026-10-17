cmake_minimum_required(VERSION 3.20)
project(MoonFactory LANGUAGES C CXX)

set(CMAKE_C_STANDARD 99)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(nlohmann_json 3.11 QUIET CONFIG)
if(NOT TARGET nlohmann_json::nlohmann_json)
    find_path(MOONMOD_NLOHMANN_JSON_INCLUDE_DIR nlohmann/json.hpp)
    if(NOT MOONMOD_NLOHMANN_JSON_INCLUDE_DIR)
        message(FATAL_ERROR
            "nlohmann/json.hpp was not found. Install nlohmann_json 3.11+ or set MOONMOD_NLOHMANN_JSON_INCLUDE_DIR.")
    endif()
    add_library(moonmod_nlohmann_json INTERFACE)
    target_include_directories(moonmod_nlohmann_json INTERFACE ${MOONMOD_NLOHMANN_JSON_INCLUDE_DIR})
    add_library(nlohmann_json::nlohmann_json ALIAS moonmod_nlohmann_json)
endif()

set(MOONMOD_LUA_DIR ${CMAKE_CURRENT_SOURCE_DIR}/vendor/lua-5.5.1/src)
file(GLOB MOONMOD_LUA_SOURCES CONFIGURE_DEPENDS ${MOONMOD_LUA_DIR}/*.c)
list(FILTER MOONMOD_LUA_SOURCES EXCLUDE REGEX "/(lua|luac|ltests)\\.c$")
add_library(moonmod_lua STATIC ${MOONMOD_LUA_SOURCES})
target_include_directories(moonmod_lua PUBLIC ${MOONMOD_LUA_DIR})
set_target_properties(moonmod_lua PROPERTIES C_STANDARD 99 C_STANDARD_REQUIRED ON)
if(UNIX AND NOT APPLE)
    target_link_libraries(moonmod_lua PUBLIC m)
endif()

add_library(moonmod STATIC
    src/api.cpp
    src/audio_api.cpp
    src/manager_ui.cpp
    src/manifest.cpp
    src/native_plugin_contract.cpp
    src/native_plugin_hash.cpp
    src/native_plugin_loader.cpp
    src/native_resource_overrides.cpp
    src/runtime.cpp
    src/lua_runtime.cpp)
target_include_directories(moonmod PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include)
target_link_libraries(moonmod PUBLIC nlohmann_json::nlohmann_json moonmod_lua)
