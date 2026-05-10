from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'

files_to_add = [
    # oslib 
    'flycast/core/oslib/oslib.cpp',
    'flycast/core/oslib/i18n.cpp',
    # pvr
    'flycast/core/hw/pvr/pvr.cpp',
    'flycast/core/hw/pvr/elan.cpp',
    # input
    'flycast/core/input/maplelink.cpp',
    # network
    'flycast/core/network/net_handshake.cpp',
    'flycast/core/network/ggpo.cpp',
    # flashrom
    'flycast/core/hw/flashrom/x76f100.cpp',
    'flycast/core/hw/flashrom/nvmem.cpp',
    # naomi
    'flycast/core/hw/naomi/netdimm.cpp',
    'flycast/core/hw/naomi/naomi.cpp',
    'flycast/core/hw/naomi/systemsp.cpp',
    'flycast/core/hw/naomi/printer.cpp',
    'flycast/core/hw/naomi/midiffb.cpp',
    # gl renderer
    'flycast/core/rend/gles/naomi2.cpp',
    # maple
    'flycast/core/hw/maple/maple_cfg.cpp',
    'flycast/core/hw/maple/maple_devs.cpp',
    # sh4
    'flycast/core/hw/sh4/sh4_cycles.cpp',
    # isofs
    'flycast/core/imgread/isofs.cpp',
    # UI
    'flycast/core/ui/vgamepad.cpp',
    'flycast/core/ui/gui_achievements.cpp',
    'flycast/core/ui/boxart/boxart.cpp',
    'flycast/core/ui/boxart/scraper.cpp',
    'flycast/core/ui/boxart/gamesdb.cpp',
    # modem/bba
    'flycast/core/hw/modem/modem.cpp',
    'flycast/core/hw/bba/bba.cpp',
    'flycast/core/hw/modem/v42bis.cpp',
    # mem
    'flycast/core/hw/mem/watch_points.cpp',
]

for file_path in files_to_add:
    try:
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error adding {file_path}: {e}")

project.save()
print("Saved.")
