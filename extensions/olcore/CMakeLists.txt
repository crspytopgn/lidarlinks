# Olcore GDExtension — the C++ physics core (libs/olcore) exposed to Godot.
#
# Built only when -DBUILD_GDEXTENSION=ON. The default `core` CI job never
# pays for it. The web build ships it too, as a wasm side module, when
# built under Emscripten (see docs/gdextension.md); the GDScript port in
# game/scripts/physics/ stays the fallback wherever the extension is
# absent (see game/addons/olcore/olcore.gdextension).
#
# godot-cpp comes from the submodule at extensions/godot-cpp, pinned to
# the commit in .gitmodules. There is no godot-4.7-stable godot-cpp
# release yet (latest tag is 4.5), so the pin is to master at a commit
# whose extension_api-4-7.json matches Godot 4.7; re-pin to the 4.7 tag
# when it lands.
#
# Wasm build (Emscripten 4.0.20, verified 2026-11-26), from the repository
# root — this file is only ever included by the root CMakeLists, which is
# what adds libs/olcore and the tools; configuring this directory on its
# own fails (the `olcore` target would be missing):
#   source ~/emsdk/emsdk_env.sh   # after `emsdk activate 4.0.20`
#   emcmake cmake -S . -B build-wasm -DCMAKE_BUILD_TYPE=Release \
#     -DBUILD_GDEXTENSION=ON -DGODOTCPP_THREADS=OFF
#   cmake --build build-wasm --target olcore_gdext --parallel
# The Emscripten version MUST match the one the Godot export templates
# were built with (4.0.20 for Godot 4.7.2 — the string is in the
# template's index.wasm). A build with 7.0.1 also failed to load in the
# browser with `function signature mismatch`, and the 4.0.20 build
# failed the same way until hidden visibility was set at compile time
# (see below): the mismatch is about default-visibility symbols
# joining the dynamic symbol table, not the Emscripten version on its
# own. Keep 4.0.20 anyway — it is the version the templates use, and
# mixing versions is untested. The standalone wasm core tests
# (libs/olcore on its own) are not affected and were first proven with
# 7.0.1.
#
# Threads OFF is load-bearing: the web preset has thread_support=false,
# so the export uses the web_dlink_nothreads_release template, and a
# side module built with -pthread/-sUSE_PTHREADS=1 cannot load into a
# single-threaded main module (it needs SharedArrayBuffer and the
# COOP/COEP headers). godot-cpp defaults GODOTCPP_THREADS=ON, so pass
# -DGODOTCPP_THREADS=OFF explicitly. The extension itself needs no
# threads (pure functions; WorkerThreadPool runs its tasks inline on
# the main thread in a nothreads export).
cmake_minimum_required(VERSION 3.20)
project(olcore_gdext LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

# The snapshot core: no Godot headers, so it is unit-tested on its own.
add_library(olcore_snapshot STATIC src/olcore_snapshot.cpp)
target_include_directories(olcore_snapshot PUBLIC src)
target_link_libraries(olcore_snapshot PUBLIC olcore)

# Hidden visibility is load-bearing for the web build and correct for
# every platform: a Godot web export loads the extension as an
# Emscripten SIDE_MODULE, and any symbol left at default visibility
# joins the dynamic symbol table. Emscripten then emits the side
# module's own functions as imports from `env`; Godot cannot supply
# them, so the loader substitutes a stub of another arity and the
# first indirect call through it aborts the engine with `function
# signature mismatch` (verified 2026-11-26: the StringName destructor
# pointer call in D_METHOD failed exactly this way). Visibility is
# fixed when a translation unit is compiled, so a link option alone
# does nothing — it must be a compile option on every target whose
# objects end up in the extension, including libs/olcore (whose
# CMakeLists adds the same flags) and godot-cpp (which already sets
# them itself). Only olcore_library_init stays exported, via
# GDE_EXPORT.
if(NOT MSVC)
  target_compile_options(olcore_snapshot PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
endif()

if(EMSCRIPTEN)
  # The extension's copy of the snapshot core, linked against
  # olcore_noexcept (no SJLJ exceptions; see libs/olcore/CMakeLists.txt).
  # The tests use olcore_snapshot + olcore above.
  add_library(olcore_snapshot_noexcept STATIC src/olcore_snapshot.cpp)
  target_include_directories(olcore_snapshot_noexcept PUBLIC src)
  target_link_libraries(olcore_snapshot_noexcept PUBLIC olcore_noexcept)
  if(NOT MSVC)
    target_compile_options(olcore_snapshot_noexcept PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
  endif()
endif()

add_executable(olcore_snapshot_tests tests/test_snapshot.cpp)
target_link_libraries(olcore_snapshot_tests PRIVATE olcore_snapshot olcore)
add_test(NAME olcore_snapshot_tests COMMAND olcore_snapshot_tests)

# The Godot binding: needs the godot-cpp submodule checked out. The
# snapshot core and its tests build without it, so the C++ parity checks
# run even where godot-cpp is absent; the shared library is skipped with
# a warning in that case.
if(NOT EXISTS ${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp/CMakeLists.txt)
  message(WARNING "godot-cpp submodule is not checked out: the GDExtension "
                  "shared library will not be built; run "
                  "git submodule update --init --recursive to build it")
  return()
endif()
# godot-cpp's CMake needs to know which extension API to target.
set(GODOTCPP_API_VERSION "4.7" CACHE STRING "" FORCE)
set(GODOTCPP_TARGET "template_release" CACHE STRING "" FORCE)
add_subdirectory(${CMAKE_CURRENT_SOURCE_DIR}/../godot-cpp ${CMAKE_CURRENT_BINARY_DIR}/godot-cpp)

add_library(olcore_gdext SHARED src/olcore_physics.cpp src/register_types.cpp)
if(EMSCRIPTEN)
  # The no-exceptions copy (see above and libs/olcore/CMakeLists.txt).
  target_link_libraries(olcore_gdext PRIVATE olcore_snapshot_noexcept olcore_noexcept godot-cpp)
else()
  target_link_libraries(olcore_gdext PRIVATE olcore_snapshot olcore godot-cpp)
endif()
if(NOT MSVC)
  # Compile-time hidden visibility (see the note on olcore_snapshot
  # above); a link option alone does not hide already-compiled symbols.
  target_compile_options(olcore_gdext PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
endif()
if(EMSCRIPTEN)
  # Explicit: Emscripten 4.0.20 does not infer a side module from -shared
  # alone (its link then pulls in crt1 and demands a main); 7.0.1 did.
  # godot-cpp's web.cmake adds -sSIDE_MODULE=1 to its own compile
  # options, but that does not reach this target's link step.
  target_link_options(olcore_gdext PRIVATE -sSIDE_MODULE=1)
endif()

# Binaries land where the .gdextension file expects them, named per
# platform (macOS needs both architectures for the universal export;
# build with -DCMAKE_OSX_ARCHITECTURES=arm64 and =x86_64 separately).
# The link step does not create the output directory, so make it here:
# on a fresh checkout (local or CI) the link otherwise fails with
# "cannot open output file .../bin/libolcore...: No such file or
# directory" and the CI job uploads no artifact.
#
# The per-configuration directories below are load-bearing, not tidy:
# multi-configuration generators (Visual Studio on the Windows CI leg,
# Xcode on the macOS legs) append a per-configuration subdirectory
# (Release/, Debug/, ...) to LIBRARY/RUNTIME_OUTPUT_DIRECTORY, so
# without them the Windows DLL lands in bin/Release/ instead of bin/.
# The CI upload step then ships the artifact with that Release/
# nesting, the export job downloads it into bin/Release/, and both the
# "Check GDExtension libraries" step and Godot's export look for the
# library flat in bin/ — so the Windows export failed with the DLL
# "not found" even though the Windows build itself had passed. The
# per-config properties pin every configuration to the flat directory
# the .gdextension file, the CI artifact and Godot all expect.
# (Single-configuration generators such as Unix Makefiles and Ninja
# ignore the per-config properties; the plain properties cover them.)
file(MAKE_DIRECTORY ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin)
set_target_properties(olcore_gdext PROPERTIES
  LIBRARY_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
  LIBRARY_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  LIBRARY_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  LIBRARY_OUTPUT_DIRECTORY_RELWITHDEBINFO ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  LIBRARY_OUTPUT_DIRECTORY_MINSIZEREL ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY_DEBUG ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY_RELEASE ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
  RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL ${CMAKE_SOURCE_DIR}/game/addons/olcore/bin
)
if(EMSCRIPTEN)
  # Web: a wasm side module, named as the web entry in olcore.gdextension
  # expects it. (CMake adds the "lib" prefix, so the OUTPUT_NAME here
  # has none — cf. the linux entry, "olcore.linux.x86_64" ->
  # "libolcore.linux.x86_64.so".) godot-cpp's web.cmake adds
  # -sSIDE_MODULE=1 itself.
  set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.web.wasm32" SUFFIX ".wasm")
elseif(APPLE)
  if(CMAKE_OSX_ARCHITECTURES MATCHES "arm64")
    set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.macos.arm64")
  else()
    set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.macos.x86_64")
  endif()
  set_target_properties(olcore_gdext PROPERTIES SUFFIX ".dylib")
elseif(WIN32)
  set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "libolcore.windows.x86_64" SUFFIX ".dll")
else()
  set_target_properties(olcore_gdext PROPERTIES OUTPUT_NAME "olcore.linux.x86_64" SUFFIX ".so")
endif()
