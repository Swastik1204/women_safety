require 'xcodeproj'
project = Xcodeproj::Project.open('Runner.xcodeproj')

project.targets.each do |target|
  puts "\n=== TARGET: #{target.name} ==="
  target.build_configurations.each do |config|
    base = config.base_configuration_reference
    puts "  #{config.name}: base_config = #{base ? base.real_path : 'NONE'}"
    fw = config.build_settings['FRAMEWORK_SEARCH_PATHS']
    puts "  #{config.name}: FRAMEWORK_SEARCH_PATHS = #{fw}" if fw
    other = config.build_settings['OTHER_LDFLAGS']
    puts "  #{config.name}: OTHER_LDFLAGS = #{other}" if other
  end
end
