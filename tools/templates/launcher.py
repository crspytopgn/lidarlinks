# SCons profile for the launcher's own export templates (docs/launcher.md),
# built by the CI `launcher-templates` job:
#   scons platform=<linuxbsd|windows|macos> target=template_release profile=tools/templates/launcher.py
#
# The launcher is a 2D Compatibility-renderer app, so its engine leaves out
# 3D, the Vulkan/D3D12/Metal renderers and every module it never uses: the
# compressed engine goes from 24.7 to 17.6 MiB on Linux (-29%). It keeps
# HTTPS (mbedtls), ZIPReader, RegEx, WebSocket, JPEG/WebP/TGA/Ogg, SVG and
# the fallback text server (English UI, no complex-script shaping needed).
# CI links ANGLE on Windows and macOS like the official templates, so poor
# native OpenGL drivers still fall back to it.
# The game keeps Godot's official templates: stripping modules from it only
# saved 2.4 MiB (the two renderers are most of the engine).
target = "template_release"
production = "yes"
lto = "full"
disable_3d = "yes"
vulkan = "no"
use_volk = "no"
d3d12 = "no"
metal = "no"
openxr = "no"
# AccessKit (screen readers, Godot 4.5+) needs its SDK at build time.
accesskit = "no"
module_csg_enabled = "no"
module_gridmap_enabled = "no"
module_navigation_2d_enabled = "no"
module_navigation_3d_enabled = "no"
module_enet_enabled = "no"
module_webrtc_enabled = "no"
module_upnp_enabled = "no"
module_multiplayer_enabled = "no"
module_jsonrpc_enabled = "no"
module_openxr_enabled = "no"
module_mobile_vr_enabled = "no"
module_webxr_enabled = "no"
module_theora_enabled = "no"
module_mp3_enabled = "no"
module_objectdb_profiler_enabled = "no"
module_lightmapper_rd_enabled = "no"
module_meshoptimizer_enabled = "no"
module_xatlas_unwrap_enabled = "no"
module_camera_enabled = "no"
module_interactive_music_enabled = "no"
module_ktx_enabled = "no"
module_dds_enabled = "no"
module_bmp_enabled = "no"
module_vhacd_enabled = "no"
module_raycast_enabled = "no"
module_gltf_enabled = "no"
module_fbx_enabled = "no"
module_jolt_physics_enabled = "no"
module_text_server_adv_enabled = "no"
module_text_server_fb_enabled = "yes"
