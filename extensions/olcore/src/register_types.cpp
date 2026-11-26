// register_types.cpp — GDExtension entry point.
#include <gdextension_interface.h>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/core/defs.hpp>
#include <godot_cpp/godot.hpp>

#include "olcore_physics.hpp"

using namespace godot;

void initialize_olcore_module(ModuleInitializationLevel p_level) {
  if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
  ClassDB::register_class<olcore_gdext::OlcoreTerrain>();
  ClassDB::register_class<olcore_gdext::OlcoreAero>();
  ClassDB::register_class<olcore_gdext::OlcoreClubs>();
  ClassDB::register_class<olcore_gdext::OlcoreLinksObjects>();
  ClassDB::register_class<olcore_gdext::OlcorePhysics>();
}

void uninitialize_olcore_module(ModuleInitializationLevel p_level) {
  if (p_level != MODULE_INITIALIZATION_LEVEL_SCENE) return;
}

extern "C" {
GDExtensionBool GDE_EXPORT olcore_library_init(GDExtensionInterfaceGetProcAddress p_get_proc_address,
                                               GDExtensionClassLibraryPtr p_library,
                                               GDExtensionInitialization* r_initialization) {
  GDExtensionBinding::InitObject init_obj(p_get_proc_address, p_library, r_initialization);
  init_obj.register_initializer(initialize_olcore_module);
  init_obj.register_terminator(uninitialize_olcore_module);
  init_obj.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
  return init_obj.init();
}
}
