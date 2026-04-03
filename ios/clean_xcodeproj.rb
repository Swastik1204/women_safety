require 'xcodeproj'
project_path = 'Runner.xcodeproj'
project = Xcodeproj::Project.open(project_path)

runner_target = project.targets.find { |t| t.name == 'Runner' }

runner_target.build_phases.each do |phase|
  if phase.is_a?(Xcodeproj::Project::Object::PBXFrameworksBuildPhase)
    phase.files.delete_if { |f| f.file_ref && f.file_ref.name == 'AppAuth.framework' }
    phase.files.delete_if { |f| f.file_ref && f.file_ref.name == 'GTMAppAuth.framework' }
    phase.files.delete_if { |f| f.file_ref && f.file_ref.name == 'GTMSessionFetcher.framework' }
  end
end

project.save
puts "Cleaned PBXFrameworksBuildPhase!"
