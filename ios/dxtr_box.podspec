#
# CocoaPods specification for the dxtr_box Flutter FFI plugin.
#
Pod::Spec.new do |s|
  s.name             = 'dxtr_box'
  s.version          = '0.4.0-dev.1'
  s.summary          = 'Rust-powered ACID NoSQL box database for Flutter.'
  s.description      = <<-DESC
Self-contained Flutter FFI plugin for dxtr_box. Native storage is built from the bundled Rust crate through Cargokit.
                       DESC
  s.homepage         = 'https://github.com/dexter-cnx/dxtr_box'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'dexter-cnx' => '73522389+dexter-cnx@users.noreply.github.com' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../rust rust_lib_dxtr_box',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/librust_lib_dxtr_box.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/librust_lib_dxtr_box.a',
  }
end
