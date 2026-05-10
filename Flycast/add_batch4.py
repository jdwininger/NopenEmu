from pbxproj import XcodeProject
import os

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'

# Tinygettext cpp files
tinygettext_files = [
    'flycast/core/deps/tinygettext/src/dictionary.cpp',
    'flycast/core/deps/tinygettext/src/dictionary_manager.cpp',
    'flycast/core/deps/tinygettext/src/iconv.cpp',
    'flycast/core/deps/tinygettext/src/language.cpp',
    'flycast/core/deps/tinygettext/src/log.cpp',
    'flycast/core/deps/tinygettext/src/plural_forms.cpp',
    'flycast/core/deps/tinygettext/src/po_parser.cpp',
    'flycast/core/deps/tinygettext/src/tinygettext.cpp',
]

# GGPO cpp files
ggpo_files = [
    'flycast/core/deps/ggpo/lib/ggpo/bitvector.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/game_input.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/input_queue.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/backends/p2p.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/backends/spectator.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/backends/synctest.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/network/udp.cpp',
    'flycast/core/deps/ggpo/lib/ggpo/network/udp_proto.cpp',
]

files_to_add = tinygettext_files + ggpo_files

for file_path in files_to_add:
    try:
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error adding {file_path}: {e}")

project.save()
print("Saved.")
