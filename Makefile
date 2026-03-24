.PHONY: build clean run-dev run-app bundle test set-version package install-cli uninstall-cli

APP_NAME = StatusBar
APP_BUNDLE = $(APP_NAME).app
DEBUG_BUNDLE = .build/debug/$(APP_BUNDLE)
CLI_NAME = sbar
CLI_INSTALL_DIR = /usr/local/bin

build:
	swift build

release:
	swift build -c release

clean:
	swift package clean
	rm -rf $(APP_BUNDLE) $(DEBUG_BUNDLE)

test:
	swift test

run-dev: build
	@-pkill -x $(APP_NAME) 2>/dev/null && sleep 0.5 || true
	@rm -rf $(DEBUG_BUNDLE)
	@mkdir -p $(DEBUG_BUNDLE)/Contents/MacOS
	@mkdir -p $(DEBUG_BUNDLE)/Contents/Frameworks
	@cp .build/debug/$(APP_NAME) $(DEBUG_BUNDLE)/Contents/MacOS/
	@cp .build/debug/$(CLI_NAME) $(DEBUG_BUNDLE)/Contents/MacOS/
	@cp .build/debug/libStatusBarKit.dylib $(DEBUG_BUNDLE)/Contents/Frameworks/
	@cp Resources/Info.plist $(DEBUG_BUNDLE)/Contents/
	@if [ -f StatusBar.entitlements ]; then \
		codesign --force --deep --entitlements StatusBar.entitlements -s - $(DEBUG_BUNDLE); \
	fi
	open $(DEBUG_BUNDLE)

run-app: bundle
	@-pkill -x $(APP_NAME) 2>/dev/null && sleep 0.5 || true
	open $(APP_BUNDLE)

bundle: release
	@echo "Creating $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Frameworks
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp .build/release/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp .build/release/$(CLI_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp .build/release/libStatusBarKit.dylib $(APP_BUNDLE)/Contents/Frameworks/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	@if [ -f StatusBar.entitlements ]; then \
		codesign --force --deep --entitlements StatusBar.entitlements -s - $(APP_BUNDLE); \
	fi
	@echo "Done: $(APP_BUNDLE)"

package: bundle
	zip -r $(APP_NAME).zip $(APP_BUNDLE)

install-cli: build
	@echo "Installing $(CLI_NAME) to $(CLI_INSTALL_DIR)..."
	@mkdir -p $(CLI_INSTALL_DIR)
	cp .build/debug/$(CLI_NAME) $(CLI_INSTALL_DIR)/$(CLI_NAME)
	@echo "Done. Run '$(CLI_NAME) --help' to get started."

uninstall-cli:
	rm -f $(CLI_INSTALL_DIR)/$(CLI_NAME)
	@echo "Removed $(CLI_NAME) from $(CLI_INSTALL_DIR)"

set-version:
	@if [ -z "$(VERSION)" ]; then echo "Usage: make set-version VERSION=x.y.z"; exit 1; fi
	/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $(VERSION)" Resources/Info.plist
	/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $(VERSION)" Resources/Info.plist
