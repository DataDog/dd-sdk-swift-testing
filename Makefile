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

build/multiplatform/dir:
	mkdir -p $(PWD)/build/multiplatform
	mkdir -p $(PWD)/build/multiplatform/DatadogSDKTesting

build/multiplatform/DatadogSDKTesting/ios: build/DatadogSDKTesting/ios
	mkdir -p $(PWD)/build/multiplatform/DatadogSDKTesting/ios
	cp -R $(PWD)/build/DatadogSDKTesting/iphoneos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework $(PWD)/build/multiplatform/DatadogSDKTesting/ios/DatadogSDKTesting.framework
	lipo -create -output build/multiplatform/DatadogSDKTesting/ios/DatadogSDKTesting.framework/DatadogSDKTesting build/DatadogSDKTesting/iphoneos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/DatadogSDKTesting build/DatadogSDKTesting/iphonesimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/DatadogSDKTesting
	cp -f build/DatadogSDKTesting/iphonesimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/Modules/DatadogSDKTesting.swiftmodule/* build/multiplatform/DatadogSDKTesting/ios/DatadogSDKTesting.framework/Modules/DatadogSDKTesting.swiftmodule/

build/multiplatform/DatadogSDKTesting/tvos: build/DatadogSDKTesting/tvos
	mkdir -p $(PWD)/build/multiplatform/DatadogSDKTesting/tvos
	cp -R $(PWD)/build/DatadogSDKTesting/appletvos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework $(PWD)/build/multiplatform/DatadogSDKTesting/tvos/DatadogSDKTesting.framework
	lipo -create -output build/multiplatform/DatadogSDKTesting/tvos/DatadogSDKTesting.framework/DatadogSDKTesting build/DatadogSDKTesting/appletvos.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/DatadogSDKTesting build/DatadogSDKTesting/appletvsimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/DatadogSDKTesting
	cp -f build/DatadogSDKTesting/appletvsimulator.xcarchive/Products/Library/Frameworks/DatadogSDKTesting.framework/Modules/DatadogSDKTesting.swiftmodule/* build/multiplatform/DatadogSDKTesting/tvos/DatadogSDKTesting.framework/Modules/DatadogSDKTesting.swiftmodule/

build/multiplatform/LICENSE: LICENSE
	cp LICENSE ./build/multiplatform/DatadogSDKTesting/LICENSE

build/multiplatform/DatadogSDKTesting: build/multiplatform/DatadogSDKTesting/ios build/multiplatform/DatadogSDKTesting/mac build/multiplatform/DatadogSDKTesting/tvos


build/multiplatform/DatadogSDKTesting.zip: build/multiplatform/LICENSE build/multiplatform/DatadogSDKTesting
	cd ./build/multiplatform/DatadogSDKTesting; zip -ry ../DatadogSDKTesting.zip ./ios ./mac ./tvos ./LICENSE


build/multiplatform: build/multiplatform/dir build/multiplatform/DatadogSDKTesting.zip

release: build/xcframework build/multiplatform

clean:
	rm -rf ./build

tests:
	xcodebuild -scheme DatadogSDKTesting_macOS -sdk macosx -destination 'platform=macOS,arch=x86_64' test
	xcodebuild -scheme DatadogSDKTesting_iOS -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 11' test
	xcodebuild -scheme DatadogSDKTesting_tvOS -sdk appletvsimulator -destination 'platform=tvOS Simulator,name=Apple TV 4K' test
