#!/bin/sh
# This script expects two inputs
# $1 - The github token for dd-sdk-swift-testing
# $2 - the git tag

#Upload binary file to release file
brew list gh &>/dev/null || brew install gh
echo $1 | gh auth login --with-token
gh release upload $2 ./build/xcframework/DatadogSDKTesting.zip --clobber

#Update binary release repo
binaryChecksum=$(swift package compute-checksum ./build/xcframework/DatadogSDKTesting.zip)
sed -E -i '' 's/let releaseVersion = ".+"/let releaseVersion = "'$2\"/ Package@swift-5.3.swift
sed -E -i '' 's/let relaseChecksum = ".+"/let relaseChecksum = "'$binaryChecksum\"/ Package@swift-5.3.swift
cat Package@swift-5.3.swift
git add Package@swift-5.3.swift
git commit -m "Updated binary package version to $2"
git tag -f $2
git push -f --tags origin HEAD:2.1-maintenance
