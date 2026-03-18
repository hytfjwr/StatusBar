.PHONY: build clean run bundle test set-version package

APP_NAME = StatusBar
APP_BUNDLE = $(APP_NAME).app

build:
	swift build

release:
	swift build -c release

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

test:
	swift test

run: build
	.build/debug/$(APP_NAME)

bundle: release
	@echo "Creating $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp .build/release/libStatusBarKit.dylib $(APP_BUNDLE)/Contents/Frameworks/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@if [ -f StatusBar.entitlements ]; then \
		codesign --force --deep --entitlements StatusBar.entitlements -s - $(APP_BUNDLE); \
	fi
	@echo "Done: $(APP_BUNDLE)"

package: bundle
	zip -r $(APP_NAME).zip $(APP_BUNDLE)

set-version:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make set-version VERSION=x.y.z"; exit 1; fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Resources/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" Resources/Info.plist

run-app: bundle
	open $(APP_BUNDLE)
