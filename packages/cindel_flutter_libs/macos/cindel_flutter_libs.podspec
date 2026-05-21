Pod::Spec.new do |s|
  s.name             = 'cindel_flutter_libs'
  s.version          = '0.0.1'
  s.summary          = 'Prebuilt native libraries for Cindel.'
  s.description      = 'Bundles Cindel native libraries for Flutter apps.'
  s.homepage         = 'https://github.com/nolbe/cindel'
  s.license          = { :type => 'Apache-2.0' }
  s.author           = { 'Cindel' => 'cindel@example.com' }
  s.source           = { :path => '.' }

  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.15'
  s.swift_version = '5.3'
  s.vendored_libraries = 'libcindel_native.dylib'
end
