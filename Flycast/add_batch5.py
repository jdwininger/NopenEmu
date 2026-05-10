from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'

files_to_add = [
    # GGPO remaining
    'flycast/core/deps/ggpo/lib/ggpo/poll.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/sync.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/timesync.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/platform_linux.cpp',
    # tinygettext unix
    'flycast/core/deps/tinygettext/src/unix_file_system.cpp',
    # virtmem (posix)
    'flycast/core/linux/posix_vmem.cpp',
    # resources
    'flycast/core/oslib/resources.cpp',
    # hopper (coin mecanism?) 
    'flycast/core/hw/naomi/hopper.cpp',
    # http client (already added, check)
    # modem files
    'flycast/core/hw/modem/v42protocol.cpp',
]

for file_path in files_to_add:
    try:
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error: {e} for {file_path}")

project.save()
print("Saved.")
