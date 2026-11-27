# C2PA Flutter Plugin - Build Automation
#
# This Makefile provides targets for building, testing, and maintaining
# the C2PA Flutter plugin.
#
# Usage:
#   make setup        - Install dependencies
#   make test         - Run all tests
#   make build        - Build for all platforms
#   make ci           - Run full CI pipeline
#   make help         - Show this help message

.PHONY: all setup test test-unit test-integration lint format format-check \
        build build-ios build-android clean coverage fixtures pigeon ci help

# Default target
all: test build

# ==============================================================================
# Setup
# ==============================================================================

## Install all dependencies
setup:
	@echo "Setting up Flutter plugin..."
	flutter pub get
	@echo "Setting up example app..."
	cd example && flutter pub get
	@echo "Setup complete!"

## Generate test fixtures (certificates and images)
fixtures:
	@echo "Generating test certificates..."
	@mkdir -p test/fixtures/certificates
	@mkdir -p test/fixtures/images
	@mkdir -p test/fixtures/manifests
	@if [ ! -f test/fixtures/certificates/test_es256_key.pem ]; then \
		openssl ecparam -name prime256v1 -genkey -noout -out test/fixtures/certificates/test_es256_key.pem 2>/dev/null || true; \
	fi
	@if [ ! -f test/fixtures/certificates/test_es256_cert.pem ]; then \
		openssl req -new -x509 -key test/fixtures/certificates/test_es256_key.pem \
			-out test/fixtures/certificates/test_es256_cert.pem -days 365 \
			-subj "/CN=C2PA Test/O=Guardian Project/C=US" 2>/dev/null || true; \
	fi
	@echo "Generating test images..."
	@if command -v convert >/dev/null 2>&1; then \
		if [ ! -f test/fixtures/images/test_unsigned.jpg ]; then \
			convert -size 100x100 xc:red test/fixtures/images/test_unsigned.jpg 2>/dev/null || true; \
		fi; \
		if [ ! -f test/fixtures/images/test_unsigned.png ]; then \
			convert -size 100x100 xc:blue test/fixtures/images/test_unsigned.png 2>/dev/null || true; \
		fi; \
	else \
		echo "ImageMagick not found, skipping image generation"; \
	fi
	@echo "Copying fixtures to example app..."
	@mkdir -p example/assets/test_images
	@mkdir -p example/assets/test_certs
	@mkdir -p example/assets/test_manifests
	@cp -f test/fixtures/certificates/*.pem example/assets/test_certs/ 2>/dev/null || true
	@cp -f test/fixtures/images/*.jpg example/assets/test_images/ 2>/dev/null || true
	@cp -f test/fixtures/images/*.png example/assets/test_images/ 2>/dev/null || true
	@cp -f test/fixtures/manifests/*.json example/assets/test_manifests/ 2>/dev/null || true
	@echo "Test fixtures ready!"

# ==============================================================================
# Testing
# ==============================================================================

## Run all tests (unit + integration where possible)
test: test-unit

## Run unit tests only
test-unit:
	@echo "Running unit tests..."
	flutter test --reporter expanded

## Run unit tests with coverage
test-coverage:
	@echo "Running unit tests with coverage..."
	flutter test --coverage --reporter expanded
	@echo "Coverage report generated in coverage/lcov.info"

## Run integration tests on iOS simulator
test-integration-ios:
	@echo "Running integration tests on iOS..."
	cd example && flutter test integration_test/ -d "iPhone"

## Run integration tests on Android emulator
test-integration-android:
	@echo "Running integration tests on Android..."
	cd example && flutter test integration_test/ -d emulator

## Run all integration tests (requires device/emulator)
test-integration: test-integration-ios

# ==============================================================================
# Code Quality
# ==============================================================================

## Run Flutter analyze (lint)
lint:
	@echo "Running Flutter analyze..."
	flutter analyze --no-fatal-infos

## Format code with dart format
format:
	@echo "Formatting Dart code..."
	dart format lib/ test/ example/lib/ example/integration_test/

# Regenerate the Dart, Kotlin and Swift bindings from pigeons/c2pa_api.dart.
pigeon:
	@echo "Generating Pigeon bindings..."
	dart run pigeon --input pigeons/c2pa_api.dart
	dart format lib/src/c2pa_api.g.dart

## Check formatting without making changes
format-check:
	@echo "Checking code formatting..."
	dart format --set-exit-if-changed lib/ test/ example/lib/ example/integration_test/

# ==============================================================================
# Building
# ==============================================================================

## Build for all platforms
build: build-ios build-android

## Build iOS only
build-ios:
	@echo "Building iOS..."
	cd example && flutter build ios --no-codesign --simulator
	@echo "iOS build complete!"

## Build Android only
build-android:
	@echo "Building Android..."
	cd example && flutter build apk --debug
	@echo "Android build complete!"

## Build iOS release (requires signing)
build-ios-release:
	@echo "Building iOS release..."
	cd example && flutter build ios --release
	@echo "iOS release build complete!"

## Build Android release
build-android-release:
	@echo "Building Android release..."
	cd example && flutter build apk --release
	@echo "Android release build complete!"

# ==============================================================================
# Coverage
# ==============================================================================

## Generate coverage report
coverage: test-coverage
	@echo "Coverage report available at coverage/lcov.info"
	@if command -v genhtml >/dev/null 2>&1; then \
		genhtml coverage/lcov.info -o coverage/html; \
		echo "HTML coverage report generated at coverage/html/index.html"; \
	else \
		echo "Install lcov for HTML coverage reports: brew install lcov"; \
	fi

## Open coverage report in browser (macOS)
coverage-open: coverage
	@if [ -f coverage/html/index.html ]; then \
		open coverage/html/index.html; \
	else \
		echo "HTML coverage report not found. Install lcov first."; \
	fi

# ==============================================================================
# Cleanup
# ==============================================================================

## Clean all build artifacts
clean:
	@echo "Cleaning build artifacts..."
	flutter clean
	cd example && flutter clean
	rm -rf coverage/
	rm -rf .dart_tool/
	rm -rf build/
	rm -rf example/build/
	rm -rf example/.dart_tool/
	@echo "Clean complete!"

## Deep clean including pub cache
clean-deep: clean
	@echo "Removing pub dependencies..."
	rm -rf .packages
	rm -rf .flutter-plugins
	rm -rf .flutter-plugins-dependencies
	rm -rf example/.packages
	rm -rf example/.flutter-plugins
	rm -rf example/.flutter-plugins-dependencies
	@echo "Deep clean complete!"

# ==============================================================================
# CI Pipeline
# ==============================================================================

## Run full CI pipeline (format check, lint, test, coverage, build)
ci: format-check lint test-unit test-coverage build
	@echo "CI pipeline complete!"

## Quick CI check (lint + test only, no build)
ci-quick: lint test-unit
	@echo "Quick CI check complete!"

# ==============================================================================
# Publishing
# ==============================================================================

## Dry run of pub publish
pub-dry:
	@echo "Running pub publish dry run..."
	flutter pub publish --dry-run

## Check package score
pub-score:
	@echo "Checking package score..."
	dart pub global activate pana
	dart pub global run pana --no-warning .

# ==============================================================================
# Development Helpers
# ==============================================================================

## Run example app on connected device
run:
	@echo "Running example app..."
	cd example && flutter run

## Run example app in release mode
run-release:
	@echo "Running example app in release mode..."
	cd example && flutter run --release

## Watch for changes and run tests
watch:
	@echo "Watching for changes..."
	flutter test --watch

## Generate API documentation
docs:
	@echo "Generating API documentation..."
	dart doc .
	@echo "Documentation generated in doc/api/"

## Open API documentation in browser
docs-open: docs
	@if [ -f doc/api/index.html ]; then \
		open doc/api/index.html; \
	fi

# ==============================================================================
# Native Development
# ==============================================================================

## Open iOS project in Xcode
xcode:
	@echo "Opening iOS project in Xcode..."
	open example/ios/Runner.xcworkspace

## Open Android project in Android Studio
android-studio:
	@echo "Opening Android project in Android Studio..."
	open -a "Android Studio" example/android

# ==============================================================================
# Help
# ==============================================================================

## Show this help message
help:
	@echo "C2PA Flutter Plugin - Build Automation"
	@echo ""
	@echo "Usage: make [target]"
	@echo ""
	@echo "Setup:"
	@echo "  setup              Install all dependencies"
	@echo "  fixtures           Generate test fixtures (certs, images)"
	@echo ""
	@echo "Testing:"
	@echo "  test               Run all tests (unit + integration)"
	@echo "  test-unit          Run unit tests only"
	@echo "  test-coverage      Run tests with coverage"
	@echo "  test-integration   Run integration tests (requires device)"
	@echo ""
	@echo "Code Quality:"
	@echo "  lint               Run Flutter analyze"
	@echo "  format             Format all Dart code"
	@echo "  format-check       Check code formatting"
	@echo "  pigeon             Regenerate the Pigeon bindings"
	@echo ""
	@echo "Building:"
	@echo "  build              Build for all platforms"
	@echo "  build-ios          Build iOS only"
	@echo "  build-android      Build Android only"
	@echo ""
	@echo "Coverage:"
	@echo "  coverage           Generate coverage report"
	@echo "  coverage-open      Open coverage in browser"
	@echo ""
	@echo "CI:"
	@echo "  ci                 Run full CI pipeline"
	@echo "  ci-quick           Quick CI check (lint + test)"
	@echo ""
	@echo "Cleanup:"
	@echo "  clean              Clean build artifacts"
	@echo "  clean-deep         Deep clean including pub cache"
	@echo ""
	@echo "Development:"
	@echo "  run                Run example app"
	@echo "  watch              Watch and run tests"
	@echo "  docs               Generate API documentation"
	@echo "  xcode              Open iOS project in Xcode"
	@echo "  android-studio     Open Android project in Android Studio"
	@echo ""
	@echo "Publishing:"
	@echo "  pub-dry            Dry run of pub publish"
	@echo "  pub-score          Check package score with pana"
