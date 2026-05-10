import sys
import os
from pbxproj import XcodeProject

project_path = "/Volumes/4TB Storage/Jeremy/Source/OpenEmu/Flycast/Flycast.xcodeproj/project.pbxproj"
project = XcodeProject.load(project_path)

target_name = 'Flycast'
targets = project.get_targets_by_name(target_name)
if not targets:
    print(f"Target {target_name} not found")
    sys.exit(1)

target = targets[0]
build_configs = project.objects.get_build_configurations(target.buildConfigurationList)

for config in build_configs:
    settings = config.buildSettings
    if 'HEADER_SEARCH_PATHS' not in settings:
        settings['HEADER_SEARCH_PATHS'] = []
    
    paths = settings['HEADER_SEARCH_PATHS']
    if isinstance(paths, str):
        paths = [paths]
    
    new_path = '"$(SRCROOT)/flycast/core/deps/imgui/backends"'
    if new_path not in paths:
        paths.append(new_path)
    
    settings['HEADER_SEARCH_PATHS'] = paths

project.save()
print("Header paths updated.")
