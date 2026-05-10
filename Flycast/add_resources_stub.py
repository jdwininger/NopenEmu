from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)
target_name = 'Flycast'

try:
    project.add_file('Compatibility/resources_stub.cpp', parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
    print("Added resources_stub.cpp")
except Exception as e:
    print(f"Error: {e}")

project.save()
print("Saved.")
