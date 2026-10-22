cmake_minimum_required(VERSION 3.22)
project(wanderville_opus LANGUAGES C CXX)

# The Opus decoder for the Godot client.
#
# Godot has no Opus decoder of its own, so the client needs one. This builds
# it from source: the official Xiph release of libopus, pinned by hash, and
# the official Godot bindings, pinned to a release branch. Nothing is taken on
# trust from a third party build, and the same file builds the extension on
# Windows, macOS and Linux.
#
# The client never depends on this being present. It only asks the server for
# Opus when the decoder actually loaded, so a build without it keeps using
# raw PCM.

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_VISIBILITY_PRESET hidden)
set(CMAKE_CXX_VISIBILITY_PRESET hidden)
set(CMAKE_VISIBILITY_INLINES_HIDDEN ON)

include(FetchContent)

# libopus, the official release, pinned by hash.
set(OPUS_BUILD_SHARED_LIBRARY OFF CACHE BOOL "" FORCE)
set(OPUS_BUILD_TESTING OFF CACHE BOOL "" FORCE)
set(OPUS_INSTALL OFF CACHE BOOL "" FORCE)
FetchContent_Declare(
    opus
    URL https://downloads.xiph.org/releases/opus/opus-1.5.2.tar.gz
    URL_HASH SHA256=65c1d2f78b9f2fb20082c38cbe47c951ad5839345876e46941612ee87f9a7ce1
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(opus)

# The Godot bindings, pinned to the 4.5 branch. An extension built against
# them loads in every later 4.x, and the branch is what the 4.6 client is
# verified against.
FetchContent_Declare(
    godot_cpp
    GIT_REPOSITORY https://github.com/godotengine/godot-cpp.git
    GIT_TAG 4.5
    GIT_SHALLOW TRUE
)
FetchContent_MakeAvailable(godot_cpp)

add_library(wanderville_opus SHARED src/opus_decoder.cpp)

target_link_libraries(wanderville_opus PRIVATE opus godot::cpp)
target_compile_definitions(wanderville_opus PRIVATE OPUS_STATIC=1)

set_target_properties(
    wanderville_opus
    PROPERTIES
        C_VISIBILITY_PRESET hidden
        CXX_VISIBILITY_PRESET hidden
        PREFIX "lib"
        # Godot loads the extension by its entry symbol, which has to be
        # exported even though everything else is hidden.
        WINDOWS_EXPORT_ALL_SYMBOLS OFF
)

if(MSVC)
    target_compile_options(wanderville_opus PRIVATE /W3)
else()
    target_compile_options(wanderville_opus PRIVATE -Wall -Wextra -Wno-unused-parameter)
endif()

if(MINGW)
    # The extension is loaded by Godot from the game's own folder, so it has
    # to stand on its own. A DLL that still needs libstdc++, libgcc or
    # libwinpthread from the build machine simply fails to load on a
    # player's computer.
    target_link_options(wanderville_opus PRIVATE -static)
endif()
