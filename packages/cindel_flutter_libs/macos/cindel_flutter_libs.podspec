Pod::Spec.new do |s|
  s.name             = 'cindel_flutter_libs'
  s.version          = '1.1.4'
  s.summary          = 'Prebuilt native libraries for Cindel.'
  s.description      = 'Bundles Cindel native libraries for Flutter apps.'
  s.homepage         = 'https://github.com/mainser/Cindel'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Alain Ramirez' => 'nolbertrg@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files = 'cindel_flutter_libs/Sources/cindel_flutter_libs/**/*.swift'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.3'
  # Flutter installs this pod via :path, which skips CocoaPods prepare_command.
  unless system('bash', File.join(__dir__, 'prepare_framework.sh'))
    raise 'Failed to extract the bundled CindelNative XCFramework'
  end
  s.preserve_paths = 'cindel_flutter_libs/CindelNative.xcframework.zip', 'prepare_framework.sh'
  s.vendored_frameworks = 'build/CindelNative.xcframework'
end
