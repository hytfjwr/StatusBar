.PHONY: build generate clean run bundle

APP_NAME = StatusBar
APP_BUNDLE = $(APP_NAME).app

build: generate
	swift build

release: generate
	swift build -c release

generate:
	swift Scripts/generate-plugin-loader.swift

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)

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

sign: bundle
	codesign --force --deep -s - $(APP_BUNDLE)

package: sign
	zip -r $(APP_NAME).zip $(APP_BUNDLE)

run-app: bundle
	open $(APP_BUNDLE)
