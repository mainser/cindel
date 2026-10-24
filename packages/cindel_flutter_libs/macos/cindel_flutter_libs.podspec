Pod::Spec.new do |s|
  s.name             = 'cindel_flutter_libs'
  s.version          = '1.1.3'
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
  s.vendored_frameworks = 'cindel_flutter_libs/CindelNative.xcframework'
end
