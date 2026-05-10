from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)
target_name = 'Flycast'

files_to_add = [
    # imgui missing tables and cjk
    'flycast/core/deps/imgui/imgui_tables.cpp',
    'flycast/core/deps/imgui/imgui_cjk.cpp',
    # glslang SPIRV files
    'flycast/core/deps/glslang/glslang/glslang/MachineIndependent/Scan.cpp',
    # hostfs / oslib storage
    'flycast/core/oslib/storage.cpp',
    'flycast/core/oslib/directory.cpp',
]

for file_path in files_to_add:
    try:
        project.add_file(file_path, parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
        print(f"Added {file_path}")
    except Exception as e:
        print(f"Error: {e} for {file_path}")

project.save()
print("Saved.")
