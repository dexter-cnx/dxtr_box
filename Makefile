.PHONY: help pub-get format format-check analyze test rust-fmt rust-clippy rust-test rust-check frb-generate native-build native-test preflight example-android example-linux example-windows example-macos example-ios

FLUTTER ?= flutter
CARGO ?= cargo
FRB ?= flutter_rust_bridge_codegen

help:
	@echo "dxtr_box developer targets"
	@echo "  make preflight      Format check + analyze + Dart/Rust tests"
	@echo "  make frb-generate   Refresh flutter_rust_bridge bindings"
	@echo "  make native-test    Native FRB round-trip test"
	@echo "  make rust-check     rustfmt + clippy + Rust tests"

pub-get:
	$(FLUTTER) pub get

format:
	dart format lib test
	$(CARGO) fmt --manifest-path rust/Cargo.toml

format-check:
	dart format --output=none --set-exit-if-changed lib test
	$(CARGO) fmt --manifest-path rust/Cargo.toml -- --check

analyze: pub-get
	$(FLUTTER) analyze

test: pub-get
	$(FLUTTER) test

rust-fmt:
	$(CARGO) fmt --manifest-path rust/Cargo.toml -- --check

rust-clippy:
	$(CARGO) clippy --manifest-path rust/Cargo.toml --all-targets -- -D warnings

rust-test:
	$(CARGO) test --manifest-path rust/Cargo.toml --all-targets

rust-check: rust-fmt rust-clippy rust-test

frb-generate: pub-get
	$(FRB) generate
	dart format lib/src/rust

native-build:
	$(CARGO) build --manifest-path rust/Cargo.toml --release

native-test: pub-get native-build
	DXTR_BOX_NATIVE_TEST=1 $(FLUTTER) test test/native_integration_test.dart --reporter expanded

preflight: format-check analyze test rust-check

example-android:
	cd example && $(FLUTTER) pub get && $(FLUTTER) build apk --debug

example-linux:
	cd example && $(FLUTTER) pub get && $(FLUTTER) build linux --debug

example-windows:
	cd example && $(FLUTTER) pub get && $(FLUTTER) build windows --debug

example-macos:
	cd example && $(FLUTTER) pub get && $(FLUTTER) build macos --debug

example-ios:
	cd example && $(FLUTTER) pub get && $(FLUTTER) build ios --debug --no-codesign
