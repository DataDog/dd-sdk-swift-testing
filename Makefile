.PHONY: clean build tests

.SECONDARY:

# Check is variable defined helper
check_defined = $(strip $(foreach 1,$1, $(call __check_defined,$1,$(strip $(value 2)))))
__check_defined = $(if $(value $1),, $(error Undefined $1$(if $2, ($2))$(if $(value @), required by target '$@')))

# params: scheme, platform, logfile, simulator
define xctest
	$(if $(filter $2,macOS),$(eval SDK=macosx)$(eval DEST='platform=macOS,arch=arm64'),)
	$(if $(filter $2,iOSsim),$(eval SDK=iphonesimulator)$(eval DEST='platform=iOS Simulator,name=$4'),)
	$(if $(filter $2,tvOSsim),$(eval SDK=appletvsimulator)$(eval DEST='platform=tvOS Simulator,name=$4'),)
	$(if $3,\
		set -o pipefail; xcodebuild -scheme $1 -sdk $(SDK) -destination $(DEST) test | tee $1-$2-$3.log | xcbeautify,\
		xcodebuild -scheme $1 -sdk $(SDK) -destination $(DEST) test)
endef

## params: scheme, sdk, destination, name, logfile
define xcarchive
	$(if $5,\
		set -o pipefail; xcodebuild archive -scheme $1 -sdk $2 -destination $3 -archivePath \
			build/$1/$4.xcarchive SKIP_INSTALL=NO | tee $1-$4-$5.log | xcbeautify,\
		xcodebuild archive -scheme $1 -sdk $2 -destination $3 -archivePath build/$1/$4.xcarchive SKIP_INSTALL=NO)
endef

build/%/iphoneos.xcarchive:
	$(call xcarchive,$*,iphoneos,'generic/platform=iOS',iphoneos,$(XC_LOG))

build/%/iphonesimulator.xcarchive:
	$(call xcarchive,$*,iphonesimulator,'generic/platform=iOS Simulator',iphonesimulator,$(XC_LOG))
	
build/%/macos.xcarchive:
	$(call xcarchive,$*,macosx,'generic/platform=macOS',macos,$(XC_LOG))

build/%/maccatalyst.xcarchive:
	$(eval platform = 'generic/platform=macOS,variant=Mac Catalyst')
	$(call xcarchive,$*,macosx,$(platform),maccatalyst,$(XC_LOG))

build/%/appletvos.xcarchive:
	$(call xcarchive,$*,appletvos,'generic/platform=tvOS',appletvos,$(XC_LOG))

build/%/appletvsimulator.xcarchive:
	$(call xcarchive,$*,appletvsimulator,'generic/platform=tvOS Simulator',appletvsimulator,$(XC_LOG))

build/xcframework/%.xcframework: \
build/%/iphoneos.xcarchive build/%/iphonesimulator.xcarchive \
build/%/macos.xcarchive build/%/maccatalyst.xcarchive \
build/%/appletvos.xcarchive build/%/appletvsimulator.xcarchive
	@mkdir -p $(PWD)/build/xcframework
	@xargs xcodebuild -create-xcframework -output $@ <<<"$(foreach archive,$^,-framework $(archive)/Products/Library/Frameworks/$*.framework)"

build/xcframework/%.zip: build/xcframework/%.xcframework
	cd ./build/xcframework/; zip -ry ./$*.zip ./$*.xcframework

build/symbols/%.zip: \
build/%/iphoneos.xcarchive build/%/iphonesimulator.xcarchive \
build/%/macos.xcarchive build/%/maccatalyst.xcarchive \
build/%/appletvos.xcarchive build/%/appletvsimulator.xcarchive
	@for archive in $^ ; do \
		name=$$(basename $$archive | cut -d'.' -f1) ;\
		mkdir -p $(PWD)/build/symbols/$*/$$name ;\
		cp -R $$archive/dSYMs/*.dSYM $(PWD)/build/symbols/$*/$$name/ ;\
	done
	@cd $(PWD)/build/symbols/$*; zip -ry ../$*.zip ./*

build: build/xcframework/DatadogSDKTesting.zip build/symbols/DatadogSDKTesting.zip

set_version:
	@:$(call check_defined, version, release version)
	sed -i "" "s|MARKETING_VERSION =.*|MARKETING_VERSION = \"$(version)\";|g" DatadogSDKTesting.xcodeproj/project.pbxproj
	sed -i "" "s|s\.version\([[:blank:]]*\)=.*|s.version\1= '$(version)'|g" DatadogSDKTesting.podspec
	sed -i "" "s|let[[:blank:]]*releaseVersion.*|let releaseVersion = \"$(version)\"|g" Package.swift

set_hash:
	$(eval HASH := $(shell swift package compute-checksum ./build/xcframework/DatadogSDKTesting.zip))
	sed -i "" "s|:sha256 =>.*|:sha256 => '$(HASH)'|g" DatadogSDKTesting.podspec
	sed -i "" "s|let[[:blank:]]*relaseChecksum.*|let relaseChecksum = \"$(HASH)\"|g" Package.swift

release:
	@$(MAKE) set_version
	@$(MAKE) build
	@$(MAKE) set_hash

github_release: release
	@:$(call check_defined, GH_TOKEN, GitHub token)
	@:$(call check_defined, GITHUB_REPOSITORY, GitHub repository with owner)
	# Update gh utility if needed
	@brew install gh || brew upgrade gh
	# Stash changes
	@git stash --include-untracked
	# Create and push branch for release
	@git checkout -b release-$(version)
	@git push -f -u origin release-$(version)
	# Get changes back
	@git stash pop
	# Commit updated xcodeproj, podspec and Package.swift
	# We will use GH API to do that, because we need a signed commit
	@gh api graphql \
  		-F githubRepository="$(GITHUB_REPOSITORY)" \
  		-F branchName="release-$(version)" \
  		-F expectedHeadOid=$$(git rev-parse HEAD) \
  		-F commitMessage="Updated binary package version to $(version)" \
  		-F files[][path]="Package.swift" -F files[][contents]=$$(base64 -i Package.swift) \
  		-F files[][path]="DatadogSDKTesting.podspec" -F files[][contents]=$$(base64 -i DatadogSDKTesting.podspec) \
		-F files[][path]="DatadogSDKTesting.xcodeproj/project.pbxproj" -F files[][contents]=$$(base64 -i DatadogSDKTesting.xcodeproj/project.pbxproj) \
  		-F 'query=@.github/api/createCommitOnBranch.gql'
	# Pull new commit
	# Reset changes to files (we already pushed them)
	@git reset --hard
	# Save untracked
	@git stash --include-untracked
	# Pull latest commit
	@git pull
	# Create tag and push it
	@git tag -f $(version)
	@git push -f --tags origin release-$(version)
	# Restore untracked
	@git stash pop
	# rename symbols file
	@rm -f build/symbols/DatadogSDKTesting.symbols.zip
	@mv build/symbols/DatadogSDKTesting.zip build/symbols/DatadogSDKTesting.symbols.zip
	# make github release
	@gh release create $(version) --prerelease --verify-tag --generate-notes \
		build/xcframework/DatadogSDKTesting.zip build/symbols/DatadogSDKTesting.symbols.zip

publish_pod:
	@:$(call check_defined, COCOAPODS_TRUNK_TOKEN, CocoaPods trunk token)
	@pod trunk push --allow-warnings DatadogSDKTesting.podspec

clean:
	rm -rf ./build

tests/unit/%:
	$(if $(IOS_SIMULATOR),,$(eval IOS_SIMULATOR = iPhone 17))
	$(if $(TVOS_SIMULATOR),,$(eval TVOS_SIMULATOR = Apple TV))
	$(call xctest,$*,macOS,$(XC_LOG),'')
	$(call xctest,$*,iOSsim,$(XC_LOG),$(IOS_SIMULATOR))
	$(call xctest,$*,tvOSsim,$(XC_LOG),$(TVOS_SIMULATOR))
	
tests/integration/%:
	$(if $(IOS_SIMULATOR),,$(eval IOS_SIMULATOR = iPhone 17))
	$(if $(TVOS_SIMULATOR),,$(eval TVOS_SIMULATOR = Apple TV))
	$(if $(filter $*,iOSsim),$(eval SIMULATOR=$(IOS_SIMULATOR)),$(eval SIMULATOR :=))
	$(if $(filter $*,tvOSsim),$(eval SIMULATOR=$(TVOS_SIMULATOR)),)
	$(call xctest,IntegrationTests,$*,$(XC_LOG),$(SIMULATOR))

tests/unit: tests/unit/EventsExporter tests/unit/DatadogSDKTesting

tests/integration: tests/integration/macOS tests/integration/iOSsim tests/integration/tvOSsim

tests: tests/unit
