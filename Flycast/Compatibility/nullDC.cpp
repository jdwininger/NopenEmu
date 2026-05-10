// nullDC.cpp - OpenEmu compatibility shim for new flycast API
//
#include "types.h"
#include "emulator.h"
#include "cfg/cfg.h"
#include "cfg/option.h"
#include "hw/maple/maple_cfg.h"
#include "OEFCBridging.h"
#include "oslib/http_client.h"
#include <string>

namespace http {
    void init() {}
    void term() {}
    int get(const std::string& /*url*/, std::vector<u8>& /*content*/, std::string& /*content_type*/) { return 0; }
}

namespace hostfs {
    std::string OEStateFilePath;

    // OpenEmu stub - screenshots not supported; return a temp path
    std::string getScreenshotsPath() {
        return "/tmp";
    }
}

void dc_SetStateName(const std::string &fileName)
{
    hostfs::OEStateFilePath = fileName;
}

int reicast_init(int argc, char* argv[])
{
    return flycast_init(argc, argv);
}

void dc_start_game(const char *path)
{
    emu.loadGame(path, nullptr);
}

void dc_resume()
{
    emu.start();
}

void dc_request_reset()
{
    emu.requestReset();
}

void LoadGameSpecificSettings()
{
    loadGameSpecificSettings();
}

// Platform stubs for OpenEmu (not needed in plugin context)
void os_SetThreadName(const char *name) {}
void os_RunInstance(int argc, const char *argv[]) {}
