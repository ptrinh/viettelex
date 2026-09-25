// engine.h — IBus engine GType for VietTelex.
#pragma once

#include <ibus.h>

// Must run once before the first engine is created (settings watcher, app-state store).
void vt_ibus_globals_init();
GType vt_ibus_engine_type();
// "create-engine" handler for IBusFactory (user_data = the GDBusConnection).
IBusEngine *vt_ibus_create_engine(IBusFactory *factory, const gchar *engineName, gpointer connection);
