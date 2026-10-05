# Adds the "Log Bank SMS" Shortcuts action to the Xcode project.
#
# `flutter create` generates ios/Runner.xcodeproj but doesn't know about
# ios/Runner/BankSmsIntent.swift, so this script registers that file with
# the Runner target and raises the minimum iOS version to 16 (App Intents
# need iOS 16). It's safe to run more than once.
#
# Usage (from the repo root, after `flutter create`):
#   ruby scripts/setup_ios.rb
#
# Needs the xcodeproj gem, which comes with CocoaPods
# (otherwise: gem install xcodeproj).

require 'xcodeproj'

PROJECT = File.expand_path('../ios/Runner.xcodeproj', __dir__)
FILE = 'BankSmsIntent.swift'
MIN_IOS = '16.0'

project = Xcodeproj::Project.open(PROJECT)
target = project.targets.find { |t| t.name == 'Runner' } or abort('Runner target not found')
group = project.main_group.find_subpath('Runner', false) or abort('Runner group not found')

if group.files.any? { |f| f.path == FILE }
  puts "#{FILE} already in project"
else
  ref = group.new_reference(FILE)
  target.add_file_references([ref])
  puts "Added #{FILE} to Runner target"
end

configs = project.build_configurations + target.build_configurations
configs.each do |config|
  current = config.build_settings['IPHONEOS_DEPLOYMENT_TARGET']
  if current.nil? || Gem::Version.new(current) < Gem::Version.new(MIN_IOS)
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = MIN_IOS
  end
end
puts "Minimum iOS version: #{MIN_IOS}"

project.save
