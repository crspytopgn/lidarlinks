cmake_minimum_required(VERSION 3.20)
project(OpenLinks2003 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

if(MSVC)
  add_compile_options(/W4 /permissive-)
else()
  add_compile_options(-Wall -Wextra -Wpedantic)
endif()

enable_testing()

# The GDExtension is off by default: it needs the godot-cpp submodule and
# a Godot 4.7 build, and the `core` CI job must stay a fast C++ check.
# Build it with -DBUILD_GDEXTENSION=ON (see docs/gdextension.md). The web
# build ships it as a wasm side module when built under Emscripten (see
# extensions/olcore/CMakeLists.txt); the GDScript port stays the fallback
# wherever the extension is absent.
# When it is on, the static libraries need position-independent code:
# the extension links them into a shared object. This must be set
# before libs/olcore is added, so its targets pick it up.
option(BUILD_GDEXTENSION "Build the Olcore GDExtension (needs godot-cpp)" OFF)
if(BUILD_GDEXTENSION)
  set(CMAKE_POSITION_INDEPENDENT_CODE ON)
endif()

# MSVC runtime: every target in this build must use the same C runtime.
# godot-cpp defaults to the static runtime (/MT) but only sets
# CMAKE_MSVC_RUNTIME_LIBRARY when it is configured — which happens after
# libs/olcore and olcore_snapshot already exist, so those targets would
# keep CMake's default dynamic runtime (/MD) while godot-cpp and
# olcore_gdext get /MT. Linking the two together fails on Windows with
# LNK2038 (MD_DynamicRelease vs MT_StaticRelease) and LNK2019 for the
# DLL-CRT imports (__imp_llround, __imp_hypot) that the /MD objects
# reference (std::hypot in libs/olcore, std::llround in
# extensions/olcore/src/olcore_snapshot.cpp). Setting it here as a
# CACHE variable, before any target is created, fixes the runtime for
# the whole build; godot-cpp's own set(... CACHE STRING ...) without
# FORCE then becomes a no-op because the cache entry already exists. A
# plain set() is not enough: it leaves the cache for godot-cpp to fill
# with its own value, which then takes effect in godot-cpp's scope and
# gives its targets a different runtime from the earlier ones (shown
# with a mock project before this change). No FORCE here on purpose: an
# explicit -DCMAKE_MSVC_RUNTIME_LIBRARY=... on the configure line still
# wins, and it applies to every target uniformly. The value below is
# godot-cpp's static default (GODOTCPP_USE_STATIC_CPP=ON,
# GODOTCPP_DEBUG_CRT=OFF): /MT, which also matches Godot itself (its
# Windows build links the C++ runtime statically) and means players
# need no Visual C++ Redistributable. The /MD alternative
# (GODOTCPP_USE_STATIC_CPP=OFF) was rejected for exactly that reason:
# it would make every player install the matching redistributable and
# put the extension on a different CRT heap from Godot. Anyone flipping
# GODOTCPP_USE_STATIC_CPP must pass a matching
# -DCMAKE_MSVC_RUNTIME_LIBRARY=... themselves. A stale local build dir
# configured before this change keeps its old cached value; reconfigure
# from a clean build dir to pick this up.
if(MSVC)
  set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>"
      CACHE STRING "Select the MSVC runtime library for use by compilers targeting the MSVC ABI.")
endif()

add_subdirectory(libs/olcore)
add_subdirectory(tools/olarc)
add_subdirectory(tools/olcourse)
add_subdirectory(tools/olobj)
add_subdirectory(tools/oldump)
add_subdirectory(tools/olcalibrate)
add_subdirectory(tools/oltex)

if(BUILD_GDEXTENSION)
  add_subdirectory(extensions/olcore)
endif()
