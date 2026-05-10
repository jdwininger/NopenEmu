import sys
import os
from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

files_to_add = [
    'flycast/core/ui/settings_about.cpp',
    'flycast/core/ui/settings_audio.cpp',
    'flycast/core/ui/settings_video.cpp',
    'flycast/core/ui/settings_network.cpp',
    'flycast/core/ui/settings_controls.cpp',
    'flycast/core/input/dreampotato.cpp',
    'flycast/core/rend/gles/opengl_driver.cpp',
    'flycast/core/hw/naomi/touchscreen.cpp',
    'flycast/core/achievements/achievements.cpp',
    'flycast/core/deps/libchdr/deps/zstd-1.5.6/lib/decompress/huf_decompress_amd64.S'
]

target_name = 'Flycast'

for file_path in files_to_add:
    try:
        # Avoid file_options bug in pbxproj format
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error adding {file_path}: {e}")

project.save()
print("Saved modifications.")
