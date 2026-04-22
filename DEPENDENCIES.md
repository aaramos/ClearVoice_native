# Dependencies

This file lists the real dependencies for ClearVoice.

ClearVoice is a native macOS Swift app, so this repo intentionally does not use a `package.json` today. There are currently no npm packages, no CocoaPods, and no Swift Package Manager package dependencies in the project itself.

## At A Glance

- App language: `Swift 5.9`
- UI framework: `SwiftUI`
- App target: macOS `26.0`
- Project generator: `XcodeGen 2.45.4` or newer
- Xcode project package dependencies: none
- npm dependencies: none

## Apple Frameworks Used By The App

- `Foundation`
  Used across the app for data models, file paths, file I/O, networking helpers, dates, and process coordination.

- `SwiftUI`
  Builds the app UI, including import, configuration, processing, setup, and review screens.

- `AppKit`
  Used for macOS-specific behavior such as opening the browser, revealing folders in Finder, and app-level window behavior.

- `AVFoundation`
  Used for audio inspection and in-app audio preview behavior.

- `UniformTypeIdentifiers`
  Used by the folder picker and file-type handling on macOS.

- `OSLog`
  Used for structured logging in audio normalization and HTTP client code.

- `CryptoKit`
  Used to verify SHA-256 fingerprints for downloaded first-run dependencies before they are unpacked or run.

- `Darwin`
  Used for a few lower-level system helpers in support code.

## Managed Runtime Tools Downloaded By ClearVoice

These are not bundled as code libraries inside the app. ClearVoice checks for them at launch and installs missing ones into:

- `~/Library/Application Support/ClearVoice/Tools`

### FFmpeg

- Role: audio conversion, normalization, cleanup, and final export support
- Packaging: downloaded as a ZIP archive and unpacked into the managed tools folder
- Architecture-specific assets:
  - Apple Silicon (`arm64`): FFmpeg `8.1`
  - Intel (`x86_64`): FFmpeg `8.1`

### DeepFilterNet

- Role: speech cleanup and enhancement model used by the `DFN` and `Hybrid` enhancement modes
- Packaging: downloaded as a direct executable binary
- Architecture-specific assets:
  - Apple Silicon (`arm64`): DeepFilterNet `0.5.6`
  - Intel (`x86_64`): DeepFilterNet `0.5.6`

## Build And Release Tooling

- `XcodeGen`
  Generates `ClearVoice.xcodeproj` from `project.yml`.

- `xcodebuild`
  Builds the app and runs tests from the command line.

- `hdiutil`
  Creates the distributable `.dmg` in `./script/build_dmg.sh`.

- `gh` CLI
  Optional, but used by the release helper scripts to publish or update GitHub Releases.

## What Is Not In Use Right Now

- `package.json` / npm packages: not used
- Swift Package Manager package dependencies: not used
- CocoaPods: not used
- Carthage: not used

## Source Of Truth

If this file and the repo ever disagree, the code and project config win. The main source files to check are:

- [project.yml](/Users/macmini/Apps/ClearVoice_native/project.yml)
- [ToolDependency.swift](/Users/macmini/Apps/ClearVoice_native/ClearVoice/Models/ToolDependency.swift)
- [README.md](/Users/macmini/Apps/ClearVoice_native/README.md)
