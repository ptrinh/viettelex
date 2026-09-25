// main.cpp — ibus-engine-viettelex. Started by ibus-daemon with --ibus (see
// viettelex.xml); without it, registers its own component (handy for development).

#include "engine.h"

#include <cstdio>
#include <cstring>

namespace {

void onDisconnected(IBusBus *, gpointer) { ibus_quit(); }

}  // namespace

int main(int argc, char **argv) {
    bool launchedByIBus = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--ibus") == 0 || std::strcmp(argv[i], "-i") == 0) launchedByIBus = true;
        else if (std::strcmp(argv[i], "--version") == 0) {
            std::printf("ibus-engine-viettelex " VT_VERSION "\n");
            return 0;
        }
    }
    ibus_init();
    IBusBus *bus = ibus_bus_new();
    if (!ibus_bus_is_connected(bus)) {
        std::fprintf(stderr, "ibus-engine-viettelex: cannot connect to ibus-daemon\n");
        return 1;
    }
    g_signal_connect(bus, "disconnected", G_CALLBACK(onDisconnected), nullptr);
    vt_ibus_globals_init();

    IBusFactory *factory = ibus_factory_new(ibus_bus_get_connection(bus));
    ibus_factory_add_engine(factory, "viettelex", vt_ibus_engine_type());
    g_signal_connect(factory, "create-engine", G_CALLBACK(vt_ibus_create_engine), ibus_bus_get_connection(bus));

    if (launchedByIBus) {
        ibus_bus_request_name(bus, "org.freedesktop.IBus.VietTelex", 0);
    } else {
        IBusComponent *component = ibus_component_new(
            "org.freedesktop.IBus.VietTelex", "VietTelex Vietnamese input method", VT_VERSION, "MIT",
            "VietTelex", "", "", "viettelex");
        ibus_component_add_engine(
            component, ibus_engine_desc_new("viettelex", "Tiếng Việt (VietTelex)", "Bộ gõ tiếng Việt Telex/VNI",
                                            "vi", "MIT", "VietTelex", "viettelex", "default"));
        ibus_bus_register_component(bus, component);
    }
    ibus_main();
    return 0;
}
