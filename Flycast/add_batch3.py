from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'

files_to_add = [
    # AT93C EEPROM
    'flycast/core/hw/flashrom/at93cxx.cpp',
    # http client
    'flycast/core/oslib/http_client.cpp',
    # tinygettext
    # need to find all .cpp in deps/tinygettext/src
    # modbba - already bba.cpp and modem.cpp in project, picoppp is prob needed  
    'flycast/core/network/picoppp.cpp',
    # ggpo library
    'flycast/core/deps/ggpo/lib/ggpo/main.cpp',
    # mouse input
    'flycast/core/input/mouse.cpp',
    # network output
    'flycast/core/network/output.cpp',
    # zip err strings
    'flycast/core/deps/libzip/lib/zip_error.c',
    'flycast/core/deps/libzip/lib/zip_error_get_sys_type.c',
    'flycast/core/deps/libzip/lib/zip_error_strerror.c',
]

for file_path in files_to_add:
    try:
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error adding {file_path}: {e}")

project.save()
print("Saved.")
