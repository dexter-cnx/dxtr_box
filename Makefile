.PHONY: help pub-get format format-check analyze test rust-fmt rust-clippy rust-test rust-test-profiles rust-check frb-generate native-build native-build-minimal native-build-encryption native-size-baseline native-test process-crash benchmark-smoke benchmark-full preflight example-android example-linux example-windows example-macos example-ios

FLUTTER ?= flutter
CARGO ?= cargo
FRB ?= flutter_rust_bridge_codegen
BENCHMARK_OPS ?= 200
BENCHMARK_FULL_OPS ?= 5000

help:
	@echo "dxtr_box developer targets"
	@echo "  make preflight            Format check + analyze + Dart/Rust tests"
	@echo "  make frb-generate         Refresh flutter_rust_bridge bindings"
	@echo "  make native-test          Native FRB round-trip test"
	@echo "  make native-build-minimal Build core CRUD/lifecycle/watch only"
	@echo "  make native-build-encryption Build minimal + encrypted open/create"
	@echo "  make native-size-baseline Measure minimal/encryption/full native artifacts"
	@echo "  make process-crash        Process-kill + reopen durability test"
	@echo "  make benchmark-smoke      dxtr_box vs hive_ce smoke benchmark"
	@echo "  make benchmark-full       Larger local benchmark run"
	@echo "  make rust-check           rustfmt + clippy + all native feature profiles"

pub-get:
	$(FLUTTER) pub get

format:
	dart format lib test example benchmark/test
	$(CARGO) fmt --manifest-path rust/Cargo.toml

format-check:
	dart format --output=none --set-exit-if-changed lib test example benchmark/test
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

rust-test-profiles:
	$(CARGO) test --manifest-path rust/Cargo.toml --all-targets --no-default-features
	$(CARGO) test --manifest-path rust/Cargo.toml --all-targets --no-default-features --features encryption
	$(CARGO) test --manifest-path rust/Cargo.toml --all-targets

rust-check: rust-fmt rust-clippy rust-test-profiles

frb-generate: pub-get
	$(FRB) generate
	dart format lib/src/rust

native-build:
	$(CARGO) build --manifest-path rust/Cargo.toml --release

native-build-minimal:
	$(CARGO) build --manifest-path rust/Cargo.toml --release --no-default-features

native-build-encryption:
	$(CARGO) build --manifest-path rust/Cargo.toml --release --no-default-features --features encryption

native-size-baseline:
	bash tool/native_size_baseline.sh

native-test: pub-get native-build
	DXTR_BOX_NATIVE_TEST=1 $(FLUTTER) test test/native_integration_test.dart --reporter expanded

process-crash:
	$(CARGO) test --manifest-path rust/Cargo.toml --test process_crash -- --nocapture

benchmark-smoke: native-build
	cd benchmark && $(FLUTTER) pub get && DXTR_BOX_BENCHMARK=1 DXTR_BOX_BENCHMARK_OPS=$(BENCHMARK_OPS) $(FLUTTER) test test/benchmark_smoke_test.dart --reporter expanded

benchmark-full: native-build
	cd benchmark && $(FLUTTER) pub get && DXTR_BOX_BENCHMARK=1 DXTR_BOX_BENCHMARK_OPS=$(BENCHMARK_FULL_OPS) $(FLUTTER) test test/benchmark_smoke_test.dart --reporter expanded

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
