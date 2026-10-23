#!/bin/sh
# Archives suppl. and uploads it to App Store Connect / TestFlight.
# Bumps the build number first: every upload needs a unique one.
set -e
cd "$(dirname "$0")/.."

BUILD=$(date +%Y%m%d%H%M)
sed -i '' "s/CURRENT_PROJECT_VERSION: \".*\"/CURRENT_PROJECT_VERSION: \"$BUILD\"/" project.yml
xcodegen generate

rm -rf build/Suppl.xcarchive
xcodebuild -project Suppl.xcodeproj -scheme Suppl -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/Suppl.xcarchive \
  -allowProvisioningUpdates archive

xcodebuild -exportArchive -archivePath build/Suppl.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath build/export \
  -allowProvisioningUpdates

echo "Uploaded build $BUILD. It shows up in TestFlight after processing (~5-15 min)."
