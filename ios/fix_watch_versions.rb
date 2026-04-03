require 'xcodeproj'

project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

watch_target = project.targets.find { |t| t.name == 'AanchalWatch' }
runner_target = project.targets.find { |t| t.name == 'Runner' }

watch_target.build_configurations.each do |config|
  config.build_settings['MARKETING_VERSION'] = '$(FLUTTER_BUILD_NAME)'
  config.build_settings['CURRENT_PROJECT_VERSION'] = '$(FLUTTER_BUILD_NUMBER)'
  
  # Also carry over the xcconfig so FLUTTER_BUILD_NAME is populated
  runner_config = runner_target.build_configurations.find { |rc| rc.name == config.name }
  if runner_config && runner_config.base_configuration_reference
    config.base_configuration_reference = runner_config.base_configuration_reference
  end
end

project.save
puts "Versions matched with Flutter config!"
