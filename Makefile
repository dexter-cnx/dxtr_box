.PHONY: help pub-get format format-check analyze test contract-check dart-doc pub-dry-run package-readiness rust-fmt rust-clippy rust-test rust-test-profiles rust-check frb-generate native-build native-build-minimal native-build-encryption native-size-baseline native-size-stability native-size-regression native-test hive-ce-migration-test query-index-test query-sort-test process-crash benchmark-smoke benchmark-full benchmark-comparison-correctness benchmark-comparison benchmark-query-index diagnose-point-read benchmark-read-path preflight published-consumer-android published-consumer-linux published-consumer-windows published-consumer-macos published-consumer-ios example-android example-linux example-windows example-macos example-ios

FLUTTER ?= flutter
CARGO ?= cargo
FRB ?= flutter_rust_bridge_codegen
BENCHMARK_OPS ?= 200
BENCHMARK_FULL_OPS ?= 5000
COMPARISON_OPS ?= 200
QUERY_BENCHMARK_SIZES ?= 100,1000,5000
QUERY_BENCHMARK_SAMPLES ?= 3
POINT_READ_ITERATIONS ?= 500
POINT_READ_SAMPLES ?= 5
READ_PATH_RUST_ITERATIONS ?= 2000
READ_PATH_DART_ITERATIONS ?= 1000
READ_PATH_SAMPLES ?= 7
READ_PATH_OUTPUT_DIR ?= $(abspath build/read-path)
SIZE_STABILITY_RUNS ?= 3
SIZE_BASE_REF ?= HEAD^
SIZE_MAX_GROWTH_BYTES ?= 65536
SIZE_MAX_GROWTH_PERCENT ?= 3

help:
	@echo "dxtr_box developer targets"
	@echo "  make preflight            Format + analyze + tests + contract + Rust checks"
	@echo "  make contract-check       Verify public exports and durable storage format identity"
	@echo "  make package-readiness    Dart docs + pub.dev dry-run on the publishable root plugin"
	@echo "  make dart-doc             Generate public API documentation"
	@echo "  make pub-dry-run          Validate the package archive with dart pub publish --dry-run"
	@echo "  make frb-generate         Refresh flutter_rust_bridge bindings"
	@echo "  make native-test          Native FRB round-trip test"
	@echo "  make hive-ce-migration-test Real Hive CE 2.19.3 migration fixtures"
	@echo "  make query-index-test     Rust full-profile query/index integration test"
	@echo "  make query-sort-test      Dart sort contract + Rust query sort integration tests"
	@echo "  make native-build-minimal Build core CRUD/lifecycle/watch only"
	@echo "  make native-build-encryption Build minimal + encrypted open/create"
	@echo "  make native-size-baseline Measure minimal/encryption/full native artifacts"
	@echo "  make native-size-stability Repeat profile builds and verify same-run size stability"
	@echo "  make native-size-regression Compare base/head native sizes with the 0.4 growth budget"
	@echo "  make process-crash        Process-kill + reopen durability test"
	@echo "  make benchmark-smoke      dxtr_box vs hive_ce smoke benchmark"
	@echo "  make benchmark-full       Larger dxtr_box vs hive_ce local benchmark"
	@echo "  make benchmark-comparison-correctness Cross-engine CRUD/reopen correctness gate"
	@echo "  make benchmark-comparison Four-engine diagnostic timing matrix"
	@echo "  make benchmark-query-index Query scan/index diagnostic benchmark matrix"
	@echo "  make diagnose-point-read  Point get/containsKey diagnostic matrix"
	@echo "  make benchmark-read-path  0.5 decomposed Rust + Dart/FRB read-path diagnostics"
	@echo "  make rust-check           rustfmt + clippy + all native feature profiles"
	@echo "  make published-consumer-linux Stage the publish payload and build an isolated Linux consumer"

pub-get:
	$(FLUTTER) pub get

format:
	dart format lib test example benchmark/lib benchmark/test tool/validate_published_consumer.dart tool/verify_public_storage_contract.dart tool/hive_ce_migration_fixture/test
	$(CARGO) fmt --manifest-path rust/Cargo.toml

format-check:
	dart format --output=none --set-exit-if-changed lib test example benchmark/lib benchmark/test tool/validate_published_consumer.dart tool/verify_public_storage_contract.dart tool/hive_ce_migration_fixture/test
	$(CARGO) fmt --manifest-path rust/Cargo.toml -- --check

analyze: pub-get
	$(FLUTTER) analyze

test: pub-get
	$(FLUTTER) test

contract-check:
	dart run tool/verify_public_storage_contract.dart

dart-doc: pub-get
	rm -rf build/doc
	dart doc --output build/doc

pub-dry-run: pub-get
	dart pub publish --dry-run --ignore-warnings

package-readiness: dart-doc pub-dry-run

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

native-size-stability:
	DXTR_BOX_SIZE_RUNS=$(SIZE_STABILITY_RUNS) bash tool/native_size_stability.sh

native-size-regression:
	DXTR_BOX_SIZE_BASE_REF=$(SIZE_BASE_REF) \
	DXTR_BOX_SIZE_MAX_GROWTH_BYTES=$(SIZE_MAX_GROWTH_BYTES) \
	DXTR_BOX_SIZE_MAX_GROWTH_PERCENT=$(SIZE_MAX_GROWTH_PERCENT) \
	bash tool/native_size_regression.sh

native-test: pub-get native-build
	LD_LIBRARY_PATH="rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="rust/target/release:$$PATH" DXTR_BOX_NATIVE_TEST=1 $(FLUTTER) test test/native_integration_test.dart --reporter expanded

hive-ce-migration-test: native-build
	cd tool/hive_ce_migration_fixture && $(FLUTTER) pub get && LD_LIBRARY_PATH="../../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../../rust/target/release:$$PATH" DXTR_BOX_NATIVE_TEST=1 $(FLUTTER) test --reporter expanded

query-index-test:
	$(CARGO) test --manifest-path rust/Cargo.toml --test query_index -- --nocapture

query-sort-test: pub-get
	$(FLUTTER) test test/query_test.dart
	$(CARGO) test --manifest-path rust/Cargo.toml --test query_index explicit_sort -- --nocapture

process-crash:
	$(CARGO) test --manifest-path rust/Cargo.toml --test process_crash -- --nocapture

benchmark-smoke: native-build
	cd benchmark && $(FLUTTER) pub get && LD_LIBRARY_PATH="../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../rust/target/release:$$PATH" DXTR_BOX_BENCHMARK=1 DXTR_BOX_BENCHMARK_OPS=$(BENCHMARK_OPS) $(FLUTTER) test test/benchmark_smoke_test.dart --reporter expanded

benchmark-full: native-build
	cd benchmark && $(FLUTTER) pub get && LD_LIBRARY_PATH="../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../rust/target/release:$$PATH" DXTR_BOX_BENCHMARK=1 DXTR_BOX_BENCHMARK_OPS=$(BENCHMARK_FULL_OPS) $(FLUTTER) test test/benchmark_smoke_test.dart --reporter expanded

benchmark-comparison-correctness: native-build
	cd benchmark && $(FLUTTER) pub get && LD_LIBRARY_PATH="../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../rust/target/release:$$PATH" DXTR_BOX_COMPARISON=1 $(FLUTTER) test test/local_database_correctness_test.dart --reporter expanded

benchmark-comparison: native-build
	cd benchmark && $(FLUTTER) pub get && LD_LIBRARY_PATH="../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../rust/target/release:$$PATH" DXTR_BOX_COMPARISON_BENCHMARK=1 DXTR_BOX_COMPARISON_OPS=$(COMPARISON_OPS) $(FLUTTER) test test/local_database_benchmark_test.dart --reporter expanded

benchmark-query-index: native-build
	cd benchmark && $(FLUTTER) pub get && LD_LIBRARY_PATH="../rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="../rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="../rust/target/release:$$PATH" DXTR_BOX_QUERY_BENCHMARK=1 DXTR_BOX_QUERY_BENCHMARK_SIZES=$(QUERY_BENCHMARK_SIZES) DXTR_BOX_QUERY_BENCHMARK_SAMPLES=$(QUERY_BENCHMARK_SAMPLES) $(FLUTTER) test test/query_index_benchmark_test.dart --reporter expanded

diagnose-point-read: native-build pub-get
	LD_LIBRARY_PATH="rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="rust/target/release:$$PATH" DXTR_BOX_POINT_READ_DIAGNOSIS=1 DXTR_BOX_POINT_READ_ITERATIONS=$(POINT_READ_ITERATIONS) DXTR_BOX_POINT_READ_SAMPLES=$(POINT_READ_SAMPLES) $(FLUTTER) test test/point_read_diagnosis_test.dart --reporter expanded

benchmark-read-path: native-build pub-get
	rm -rf "$(READ_PATH_OUTPUT_DIR)"
	mkdir -p "$(READ_PATH_OUTPUT_DIR)"
	DXTR_BOX_READ_PATH_RUST_ITERATIONS=$(READ_PATH_RUST_ITERATIONS) DXTR_BOX_READ_PATH_RUST_SAMPLES=$(READ_PATH_SAMPLES) DXTR_BOX_READ_PATH_RUST_OUTPUT="$(READ_PATH_OUTPUT_DIR)/rust-read-path.jsonl" $(CARGO) test --manifest-path rust/Cargo.toml --release read_path_bench::read_path_microbench -- --ignored --nocapture
	LD_LIBRARY_PATH="rust/target/release:$${LD_LIBRARY_PATH:-}" DYLD_LIBRARY_PATH="rust/target/release:$${DYLD_LIBRARY_PATH:-}" PATH="rust/target/release:$$PATH" DXTR_BOX_READ_PATH_BENCHMARK=1 DXTR_BOX_READ_PATH_DART_ITERATIONS=$(READ_PATH_DART_ITERATIONS) DXTR_BOX_READ_PATH_DART_SAMPLES=$(READ_PATH_SAMPLES) DXTR_BOX_READ_PATH_DART_OUTPUT="$(READ_PATH_OUTPUT_DIR)/dart-read-path.jsonl" $(FLUTTER) test test/read_path_benchmark_test.dart --reporter expanded
	test -s "$(READ_PATH_OUTPUT_DIR)/rust-read-path.jsonl"
	test -s "$(READ_PATH_OUTPUT_DIR)/dart-read-path.jsonl"

preflight: format-check analyze test contract-check rust-check

published-consumer-android:
	dart run tool/validate_published_consumer.dart --platform=android

published-consumer-linux:
	dart run tool/validate_published_consumer.dart --platform=linux

published-consumer-windows:
	dart run tool/validate_published_consumer.dart --platform=windows

published-consumer-macos:
	dart run tool/validate_published_consumer.dart --platform=macos

published-consumer-ios:
	dart run tool/validate_published_consumer.dart --platform=ios

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
