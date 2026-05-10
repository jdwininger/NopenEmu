from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'

# Remove non-existent file and add correct one
try:
    project.remove_file_by_path('flycast/core/hw/mem/watch_points.cpp')
    print("Removed watch_points.cpp")
except Exception as e:
    print(f"Remove error: {e}")

try:
    project.add_file('flycast/core/hw/mem/mem_watch.cpp', parent=None, tree='SOURCE_ROOT', target_name=target_name, force=False)
    print("Added mem_watch.cpp")
except Exception as e:
    print(f"Add error: {e}")

project.save()
print("Saved.")
