APP_NAME := Hex Picker
BUNDLE := build/$(APP_NAME).app
DMG := build/HexPicker.dmg
INSTALL_DIR := /Applications
LSREGISTER := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

.PHONY: build sign dmg install reinstall uninstall run clean

build:
	@mkdir -p "$(BUNDLE)/Contents/MacOS" "$(BUNDLE)/Contents/Resources"
	swiftc -O -parse-as-library -o "$(BUNDLE)/Contents/MacOS/hex_picker" main.swift
	cp Info.plist "$(BUNDLE)/Contents/"
	cp design/AppIcon.icns "$(BUNDLE)/Contents/Resources/"

sign: build
	codesign --force --sign - "$(BUNDLE)"

dmg: sign
	@rm -rf build/dmg_staging
	@mkdir -p build/dmg_staging
	cp -R "$(BUNDLE)" build/dmg_staging/
	ln -s /Applications build/dmg_staging/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder build/dmg_staging -ov -format UDZO "$(DMG)"
	@rm -rf build/dmg_staging

install: sign
	@echo "Installing to $(INSTALL_DIR)..."
	-pkill -f "hex_picker" 2>/dev/null; sleep 0.5
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@./uninstall.sh --keep-installed
	@echo "Installed."

uninstall:
	./uninstall.sh

reinstall: sign
	@echo "Reinstalling..."
	-pkill -f "hex_picker" 2>/dev/null; sleep 0.5
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R "$(BUNDLE)" "$(INSTALL_DIR)/"
	@./uninstall.sh --keep-installed
	open "$(INSTALL_DIR)/$(APP_NAME).app"
	@echo "Done."

run: sign
	-pkill -f "hex_picker" 2>/dev/null; sleep 0.5
	open "$(BUNDLE)"

clean:
	-@[ -d "$(BUNDLE)" ] && "$(LSREGISTER)" -u "$(CURDIR)/$(BUNDLE)" 2>/dev/null || true
	-@[ -d "build/dmg_staging/$(APP_NAME).app" ] && "$(LSREGISTER)" -u "$(CURDIR)/build/dmg_staging/$(APP_NAME).app" 2>/dev/null || true
	rm -rf build
