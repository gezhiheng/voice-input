APP_NAME ?= VoiceInput
BUNDLE_ID ?= com.example.VoiceInput
PRODUCT_NAME ?= VoiceInput
BUILD_CONFIGURATION ?= release
DIST_DIR ?= dist
ICON_NAME ?= AppIcon
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
BIN_PATH := $(shell swift build -c $(BUILD_CONFIGURATION) --show-bin-path)
EXECUTABLE_PATH := $(BIN_PATH)/$(PRODUCT_NAME)
ICONSET_PATH := $(DIST_DIR)/$(ICON_NAME).iconset
ICON_FILE := $(APP_BUNDLE)/Contents/Resources/$(ICON_NAME).icns
DEFAULT_SIGNING_IDENTITY := $(shell security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}')
SIGNING_IDENTITY ?= $(DEFAULT_SIGNING_IDENTITY)
SIGNING_IDENTITY_EFFECTIVE := $(if $(strip $(SIGNING_IDENTITY)),$(SIGNING_IDENTITY),-)

.PHONY: build run install clean

build:
	swift build -c $(BUILD_CONFIGURATION)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(EXECUTABLE_PATH)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	rm -rf "$(ICONSET_PATH)"
	mkdir -p "$(ICONSET_PATH)"
	xcrun swift -e 'import AppKit; import Foundation; let out = URL(fileURLWithPath: CommandLine.arguments[1]); let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!; rep.size = NSSize(width: 1024, height: 1024); NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep); let context = NSGraphicsContext.current!.cgContext; context.setFillColor(NSColor.clear.cgColor); context.fill(CGRect(x: 0, y: 0, width: 1024, height: 1024)); let backgroundRect = CGRect(x: 88, y: 88, width: 848, height: 848); let backgroundPath = NSBezierPath(roundedRect: backgroundRect, xRadius: 212, yRadius: 212); NSColor(calibratedWhite: 0.47, alpha: 1.0).setFill(); backgroundPath.fill(); let topGlow = NSGradient(colors: [NSColor.white.withAlphaComponent(0.12), NSColor.clear])!; topGlow.draw(in: NSBezierPath(roundedRect: backgroundRect, xRadius: 212, yRadius: 212), angle: 90); let symbolConfig = NSImage.SymbolConfiguration(pointSize: 500, weight: .medium).applying(NSImage.SymbolConfiguration(hierarchicalColor: .white)); let symbol = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: nil)!.withSymbolConfiguration(symbolConfig)!; let symbolRect = CGRect(x: 292, y: 180, width: 440, height: 664); symbol.draw(in: symbolRect, from: .zero, operation: .sourceOver, fraction: 1.0); NSGraphicsContext.restoreGraphicsState(); let pngData = rep.representation(using: .png, properties: [:])!; try pngData.write(to: out)' "$(ICONSET_PATH)/icon_512x512@2x.png"
	sips -z 512 512 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_512x512.png" >/dev/null
	sips -z 256 256 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_256x256.png" >/dev/null
	sips -z 512 512 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_256x256@2x.png" >/dev/null
	sips -z 128 128 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_128x128.png" >/dev/null
	sips -z 256 256 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_128x128@2x.png" >/dev/null
	sips -z 32 32 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_16x16@2x.png" >/dev/null
	sips -z 16 16 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_16x16.png" >/dev/null
	sips -z 64 64 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_32x32@2x.png" >/dev/null
	sips -z 32 32 "$(ICONSET_PATH)/icon_512x512@2x.png" --out "$(ICONSET_PATH)/icon_32x32.png" >/dev/null
	iconutil --convert icns "$(ICONSET_PATH)" --output "$(ICON_FILE)"
	rm -rf "$(ICONSET_PATH)"
	plutil -create xml1 "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleDevelopmentRegion -string en "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleIconFile -string "$(ICON_NAME)" "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleExecutable -string "$(APP_NAME)" "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleIdentifier -string "$(BUNDLE_ID)" "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleInfoDictionaryVersion -string 6.0 "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleName -string "$(APP_NAME)" "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundlePackageType -string APPL "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleShortVersionString -string 1.0 "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert CFBundleVersion -string 1 "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert LSMinimumSystemVersion -string 14.0 "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert LSUIElement -bool YES "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert NSMicrophoneUsageDescription -string "VoiceInput records speech while Fn is held." "$(APP_BUNDLE)/Contents/Info.plist"
	plutil -insert NSSpeechRecognitionUsageDescription -string "VoiceInput converts your speech to text for injection into the active field." "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign "$(SIGNING_IDENTITY_EFFECTIVE)" --timestamp=none "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	mkdir -p "$(HOME)/Applications"
	rm -rf "$(HOME)/Applications/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(HOME)/Applications/$(APP_NAME).app"

clean:
	rm -rf .build "$(DIST_DIR)"
