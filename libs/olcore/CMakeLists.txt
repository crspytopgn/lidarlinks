enable_testing()

set(OLCORE_SOURCES
  src/ball_physics.cpp
  src/arc0.cpp
  src/binary_reader.cpp
  src/btcv.cpp
  src/bunky.cpp
  src/course.cpp
  src/course_areas.cpp
  src/course_objects.cpp
  src/crz.cpp
  src/carrera_store.cpp
  src/golfer_anim.cpp
  src/golfer_mesh.cpp
  src/image.cpp
  src/cvt.cpp
  src/d3f.cpp
  src/inflate.cpp
  src/links_flight.cpp
  src/links_ground.cpp
  src/links_objects.cpp
  src/links_launch.cpp
  src/links_mouse.cpp
  src/resumable_shot.cpp
  src/ls_archive.cpp
  src/lzw.cpp
  src/model.cpp
  src/obstacles.cpp
  src/opponent.cpp
  src/panorama.cpp
  src/object_library.cpp
  src/rules.cpp
  src/scoring.cpp
  src/shadow_file.cpp
  src/shot.cpp
  src/ssf.cpp
  src/strings.cpp
  src/swing.cpp
  src/terrain_mapping.cpp
  src/wav.cpp
)
add_library(olcore STATIC ${OLCORE_SOURCES})
target_include_directories(olcore PUBLIC include)

# Hidden visibility at compile time: the extension links this library
# into a wasm side module (and into the desktop .so/.dll/.dylib), and
# any symbol left at default visibility joins the dynamic symbol
# table, which the web loader then stubs with the wrong arity (see
# extensions/olcore/CMakeLists.txt). Harmless for the native test
# executables, which link statically.
if(NOT MSVC)
  target_compile_options(olcore PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
endif()

if(EMSCRIPTEN)
  # A second copy of the library without SJLJ exceptions, for the
  # GDExtension only. The `olcore` copy above is compiled with
  # -fexceptions so the standalone wasm tests can catch the loaders'
  # ReadError/InflateError, but that emits `invoke_*` calls (SJLJ
  # landing pads) in every object, including the sim files the
  # extension uses. The Godot web template does not export `invoke_*`
  # (the engine is not built with SJLJ exceptions), so the loader
  # stubs them and the first sim call in the browser fails with
  # `TypeError: resolved is not a function` (verified 2026-11-26).
  # The extension never calls a throwing function (no loaders, no
  # decompression in the sim path), so compiling its copy without
  # exceptions is safe; a throw there would abort instead of unwind,
  # which cannot happen on the paths the extension uses.
  add_library(olcore_noexcept STATIC ${OLCORE_SOURCES})
  target_include_directories(olcore_noexcept PUBLIC include)
  if(NOT MSVC)
    target_compile_options(olcore_noexcept PRIVATE -fvisibility=hidden -fvisibility-inlines-hidden)
  endif()
endif()

# Lets `ctest` work when this directory is configured on its own (the
# root CMakeLists also calls enable_testing(); calling it again here is
# harmless).
include(CTest)

if(EMSCRIPTEN)
  # C++ exceptions: the loaders throw ReadError/InflateError and the
  # tests catch them; Emscripten disables exception catching by default,
  # so a wasm build without this aborts in test_reader_bounds (the first
  # test that throws and catches). Scoped to this library and the test
  # executables on purpose: -fexceptions must never reach a target that
  # also gets godot-cpp's -sSUPPORT_LONGJMP=wasm — clang rejects that
  # combination — and the extension's own targets never throw or catch
  # (see extensions/olcore/CMakeLists.txt). The library objects carry
  # the exception tables; the test links add -fexceptions so the
  # catching runtime is linked in.
  target_compile_options(olcore PRIVATE -fexceptions)
endif()

add_executable(olcore_tests tests/test_main.cpp)
target_link_libraries(olcore_tests PRIVATE olcore)
add_test(NAME olcore_tests COMMAND olcore_tests)

add_executable(olcourse_tests tests/test_course.cpp)
target_link_libraries(olcourse_tests PRIVATE olcore)
add_test(NAME olcourse_tests COMMAND olcourse_tests)

add_executable(olcvt_tests tests/test_cvt.cpp)
target_link_libraries(olcvt_tests PRIVATE olcore)
add_test(NAME olcvt_tests COMMAND olcvt_tests)

if(EMSCRIPTEN)
  foreach(_olcore_test olcore_tests olcourse_tests olcvt_tests)
    target_compile_options(${_olcore_test} PRIVATE -fexceptions)
    target_link_options(${_olcore_test} PRIVATE -fexceptions)
  endforeach()
endif()
