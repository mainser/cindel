Pod::Spec.new do |s|
  s.name             = 'cindel_flutter_libs'
  s.version          = '0.7.0'
  s.summary          = 'Prebuilt native libraries for Cindel.'
  s.description      = 'Bundles Cindel native libraries for Flutter apps.'
  s.homepage         = 'https://github.com/mainser/cindel'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Alain Ramirez' => 'nolbertrg@gmail.com' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.3'
  s.vendored_frameworks = 'cindel.xcframework'
end
