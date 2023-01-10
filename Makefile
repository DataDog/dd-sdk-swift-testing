.PHONY: clean release tests

build/DatadogSDKTesting/ios:
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination "generic/platform=iOS" -archivePath build/DatadogSDKTesting/iphoneos.xcarchive -sdk iphoneos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination "generic/platform=iOS Simulator" -archivePath build/DatadogSDKTesting/iphonesimulator.xcarchive -sdk iphonesimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting/mac:
	xcodebuild archive -scheme DatadogSDKTesting_macOS -destination "generic/platform=macOS" -archivePath build/DatadogSDKTesting/macos.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination "generic/platform=macOS,variant=Mac Catalyst" -archivePath build/DatadogSDKTesting/maccatalyst.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES


build/DatadogSDKTesting/tvos:
	xcodebuild archive -scheme DatadogSDKTesting_tvOS -destination "generic/platform=tvOS" -archivePath build/DatadogSDKTesting/appletvos.xcarchive -sdk appletvos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_tvOS -destination "generic/platform=tvOS Simulator" -archivePath build/DatadogSDKTesting/appletvsimulator.xcarchive -sdk appletvsimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting.xcframework: build/DatadogSDKTesting/ios build/DatadogSDKTesting/mac build/DatadogSDKTesting/tvos
	mkdir -p $(PWD)/build/xcframework
	xcodebuild -create-xcframework -framework build/DatadogSDKTesting/macos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphoneos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphonesimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/appletvos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework  -framework build/DatadogSDKTesting/appletvsimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -output build/xcframework/DatadogSDKTesting.xcframework

build/xcframework/DatadogSDKTesting.zip: build/DatadogSDKTesting.xcframework
	cd ./build/xcframework/; zip -ry ./DatadogSDKTesting.zip ./DatadogSDKTesting.xcframework

build/xcframework: build/xcframework/DatadogSDKTesting.zip


release: build/xcframework

bump:
		@read -p "Enter version number: " version;  \
		sed -i "" "s/MARKETING_VERSION = .*/MARKETING_VERSION = $$version;/" DatadogSDKTesting.xcodeproj/project.pbxproj; \
		sed "s/__DATADOG_VERSION__/$$version/g" DatadogSDKTesting.podspec.src > DatadogSDKTesting.podspec; \
		git add . ; \
		git commit -m "Bumped version to $$version"; \
		echo Bumped version to $$version

clean:
	rm -rf ./build

tests:
	xcodebuild -scheme DatadogSDKTesting_macOS -sdk macosx -destination 'platform=macOS,arch=x86_64' test
	xcodebuild -scheme DatadogSDKTesting_iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 14' test
	xcodebuild -scheme DatadogSDKTesting_tvOS -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test

test-macOS:
	xcodebuild -scheme 'IntegrationTests (macOS)' -sdk macosx -destination 'platform=macOS,arch=x86_64' test

test-iOS:
	xcodebuild -scheme 'IntegrationTests (iOS)' -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 13' test

test-tvOS:
	xcodebuild -scheme 'IntegrationTests (tvOS)' -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV' test
