.PHONY: clean build tests

# Check is variable defined helper
check_defined = $(strip $(foreach 1,$1, $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = $(if $(value $1),, $(error Undefined $1$(if $2, ($2))$(if $(value @), required by target '$@')))

build/DatadogSDKTesting/ios:
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=iOS" -archivePath build/DatadogSDKTesting/iphoneos.xcarchive -sdk iphoneos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=iOS Simulator" -archivePath build/DatadogSDKTesting/iphonesimulator.xcarchive -sdk iphonesimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting/mac:
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=macOS" -archivePath build/DatadogSDKTesting/macos.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=macOS,variant=Mac Catalyst" -archivePath build/DatadogSDKTesting/maccatalyst.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES


build/DatadogSDKTesting/tvos:
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=tvOS" -archivePath build/DatadogSDKTesting/appletvos.xcarchive -sdk appletvos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting -destination "generic/platform=tvOS Simulator" -archivePath build/DatadogSDKTesting/appletvsimulator.xcarchive -sdk appletvsimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting.xcframework: build/DatadogSDKTesting/ios build/DatadogSDKTesting/mac build/DatadogSDKTesting/tvos
	mkdir -p $(PWD)/build/xcframework
	xcodebuild -create-xcframework -framework build/DatadogSDKTesting/macos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphoneos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphonesimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/appletvos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework  -framework build/DatadogSDKTesting/appletvsimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -output build/xcframework/DatadogSDKTesting.xcframework

build/xcframework/DatadogSDKTesting.zip: build/DatadogSDKTesting.xcframework
	cd ./build/xcframework/; zip -ry ./DatadogSDKTesting.zip ./DatadogSDKTesting.xcframework

build/xcframework: build/xcframework/DatadogSDKTesting.zip

collect_symbols:
	mkdir -p $(PWD)/build/symbols
	mkdir -p $(PWD)/build/symbols/macos
	cp -R build/DatadogSDKTesting/macos.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/macos/DatadogSDKTesting.framework.dSYM
	mkdir -p $(PWD)/build/symbols/iphoneos
	cp -R build/DatadogSDKTesting/iphoneos.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/iphoneos/DatadogSDKTesting.framework.dSYM
	mkdir -p $(PWD)/build/symbols/iphonesimulator
	cp -R build/DatadogSDKTesting/iphonesimulator.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/iphonesimulator/DatadogSDKTesting.framework.dSYM
	mkdir -p $(PWD)/build/symbols/appletvos
	cp -R build/DatadogSDKTesting/appletvos.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/appletvos/DatadogSDKTesting.framework.dSYM
	mkdir -p $(PWD)/build/symbols/appletvsimulator
	cp -R build/DatadogSDKTesting/appletvsimulator.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/appletvsimulator/DatadogSDKTesting.framework.dSYM
	mkdir -p $(PWD)/build/symbols/maccatalyst
	cp -R build/DatadogSDKTesting/maccatalyst.xcarchive/dSYMs/DatadogSDKTesting.framework.dSYM $(PWD)/build/symbols/maccatalyst/DatadogSDKTesting.framework.dSYM
	cd ./build/; zip -ry ./symbols.zip ./symbols

build: build/xcframework collect_symbols

set_version:
	@:$(call check_defined, version, release version)
	sed -i "" "s|MARKETING_VERSION =.*|MARKETING_VERSION = $(version);|g" DatadogSDKTesting.xcodeproj/project.pbxproj
	sed -i "" "s|s\.version\([[:blank:]]*\)=.*|s.version\1= '$(version)'|g" DatadogSDKTesting.podspec
	sed -i "" "s|let[[:blank:]]*releaseVersion.*|let releaseVersion = \"$(version)\"|g" Package.swift

set_hash:
	$(eval HASH := $(shell swift package compute-checksum ./build/xcframework/DatadogSDKTesting.zip))
	sed -i "" "s|:sha256 =>.*|:sha256 => '$(HASH)'|g" DatadogSDKTesting.podspec
	sed -i "" "s|let[[:blank:]]*relaseChecksum.*|let relaseChecksum = \"$(HASH)\"|g" Package.swift
	
release: set_version build set_hash

github: release
	@:$(call check_defined, version, release version)
	@:$(call check_defined, GITHUB_TOKEN, GitHub token)
	# Upload binary file to GitHub release
	brew list gh &>/dev/null || brew install gh
	@echo $(GITHUB_TOKEN) | gh auth login --with-token
	gh release upload $(version) ./build/xcframework/DatadogSDKTesting.zip --clobber
	gh release upload $(version) ./build/symbols.zip --clobber
	# Commit updated xcodeproj, Package.swift and DatadogSDKTesting.podspec
	git add Package.swift DatadogSDKTesting.podspec DatadogSDKTesting.xcodeproj/project.pbxproj
	git checkout -b update-binary
	git commit -m "Updated binary package version to $(version)"
	git tag -f $(version)
	git push -f --tags origin update-binary
	
clean:
	rm -rf ./build

tests/unit/exporter:
	xcodebuild -scheme EventsExporter -sdk macosx -destination 'platform=macOS,arch=x86_64' test
	xcodebuild -scheme EventsExporter -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test
	xcodebuild -scheme EventsExporter -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test

tests/unit/exporter/pretty:
	set -o pipefail; xcodebuild -scheme EventsExporter -sdk macosx -destination 'platform=macOS,arch=x86_64' test | xcbeautify --renderer github-actions
	set -o pipefail; xcodebuild -scheme EventsExporter -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test | xcbeautify --renderer github-actions
	set -o pipefail; xcodebuild -scheme EventsExporter -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test | xcbeautify --renderer github-actions

tests/unit/sdk:
	xcodebuild -scheme DatadogSDKTesting -sdk macosx -destination 'platform=macOS,arch=x86_64' test
	xcodebuild -scheme DatadogSDKTesting -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test
	xcodebuild -scheme DatadogSDKTesting -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test

tests/unit/sdk/pretty:
	set -o pipefail; xcodebuild -scheme DatadogSDKTesting -sdk macosx -destination 'platform=macOS,arch=x86_64' test | xcbeautify --renderer github-actions
	set -o pipefail; xcodebuild -scheme DatadogSDKTesting -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test | xcbeautify --renderer github-actions
	set -o pipefail; xcodebuild -scheme DatadogSDKTesting -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test | xcbeautify --renderer github-actions

tests/integration/macOS:
	xcodebuild -scheme IntegrationTests -sdk macosx -destination 'platform=macOS,arch=x86_64' test

tests/integration/iOS:
	xcodebuild -scheme IntegrationTests -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test

tests/integration/tvOS:
	xcodebuild -scheme IntegrationTests -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test

tests/unit: tests/unit/exporter tests/unit/sdk

tests/unit/pretty: tests/unit/exporter/pretty tests/unit/sdk/pretty

tests/integration: tests/integration/macOS tests/integration/iOS tests/integration/tvOS

tests: tests/unit
