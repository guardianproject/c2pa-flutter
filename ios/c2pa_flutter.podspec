# This podspec is intentionally minimal. It exists only to satisfy Flutter's
# plugin validation on platforms where CocoaPods is checked. iOS builds must
# use Swift Package Manager (see ios/c2pa_flutter/Package.swift).
#
# To enable SPM in your Flutter project:
#   flutter config --enable-swift-package-manager

Pod::Spec.new do |s|
  s.name             = 'c2pa_flutter'
  s.version          = '0.0.1'
  s.summary          = 'C2PA Flutter plugin - requires Swift Package Manager'
  s.description      = <<-DESC
Flutter plugin for C2PA content authenticity. iOS builds require Swift Package Manager.
CocoaPods is not supported. Enable SPM with: flutter config --enable-swift-package-manager
                       DESC
  s.homepage         = 'https://github.com/guardianproject/c2pa-flutter'
  s.license          = { :type => 'MIT', :file => '../LICENSE' }
  s.author           = { 'Guardian Project' => 'support@guardianproject.info' }
  s.source           = { :path => '.' }
  s.source_files     = 'cocoapods_stub/**/*.swift'
  s.platform         = :ios, '16.0'
  s.swift_version    = '5.9'
  s.dependency 'Flutter'
end
