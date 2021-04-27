.PHONY: clean release tests

build/DatadogSDKTesting/ios:
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination="iOS" -archivePath build/DatadogSDKTesting/iphoneos.xcarchive -sdk iphoneos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination="iOS Simulator" -archivePath build/DatadogSDKTesting/iphonesimulator.xcarchive -sdk iphonesimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting/mac:
	xcodebuild archive -scheme DatadogSDKTesting_macOS -archivePath build/DatadogSDKTesting/macos.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_iOS -destination 'platform=macOS,arch=x86_64,variant=Mac Catalyst' -archivePath build/DatadogSDKTesting/maccatalyst.xcarchive -sdk macosx SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES


build/DatadogSDKTesting/tvos:
	xcodebuild archive -scheme DatadogSDKTesting_tvOS -destination="tvOS" -archivePath build/DatadogSDKTesting/appletvos.xcarchive -sdk appletvos SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES
	xcodebuild archive -scheme DatadogSDKTesting_tvOS -destination="tvOS Simulator" -archivePath build/DatadogSDKTesting/appletvsimulator.xcarchive -sdk appletvsimulator SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES

build/DatadogSDKTesting.xcframework: build/DatadogSDKTesting/ios build/DatadogSDKTesting/mac build/DatadogSDKTesting/tvos
	mkdir -p $(PWD)/build/xcframework
	xcodebuild -create-xcframework -framework build/DatadogSDKTesting/macos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphoneos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/iphonesimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -framework build/DatadogSDKTesting/appletvos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework  -framework build/DatadogSDKTesting/appletvsimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework -output build/xcframework/DatadogSDKTesting.xcframework

build/xcframework/LICENSE: LICENSE
	cp LICENSE ./build/xcframework/LICENSE

build/xcframework/DatadogSDKTesting.zip: build/DatadogSDKTesting.xcframework build/xcframework/LICENSE
	cd ./build/xcframework/; zip -ry ./DatadogSDKTesting.zip ./DatadogSDKTesting.xcframework ./LICENSE

build/xcframework: build/xcframework/DatadogSDKTesting.zip


release: build/xcframework

clean:
	rm -rf ./build

tests:
	xcodebuild -scheme DatadogSDKTesting_macOS -sdk macosx -destination 'platform=macOS,arch=x86_64' test
	xcodebuild -scheme DatadogSDKTesting_iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 11' test
	xcodebuild -scheme DatadogSDKTesting_tvOS -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV 4K (2nd generation)' test
	# xcodebuild -scheme IntegrationTestsApp -sdk macosx -destination 'platform=macOS,arch=x86_64' test
