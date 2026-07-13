#!/bin/sh
set -eu

PACKAGE_SWIFT="ios/Flutter/ephemeral/Packages/FlutterGeneratedPluginSwiftPackage/Package.swift"
TARGET_VERSION="15.5"

if [ ! -f "$PACKAGE_SWIFT" ]; then
  echo "SwiftPM plugin package not found yet: $PACKAGE_SWIFT"
  echo "Run flutter pub get or build once, then rerun this script."
  exit 0
fi

perl -0pi -e "s/\\.iOS\\(\"[0-9.]+\"\\)/.iOS(\"$TARGET_VERSION\")/" "$PACKAGE_SWIFT"
echo "Set FlutterGeneratedPluginSwiftPackage iOS target to $TARGET_VERSION."
