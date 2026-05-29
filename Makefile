# Makefile — convenience wrappers around xcodegen + xcodebuild

PROJECT  := ClipboardManager.xcodeproj
SCHEME   := ClipboardManager
DEST     := platform=macOS
CONFIG   := Debug

.PHONY: gen build test run clean

gen:
	xcodegen generate

build: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -destination "$(DEST)" build

test: gen
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -destination "$(DEST)" test

run: build
	@SETTINGS=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null); \
	DIR=$$(echo "$$SETTINGS" | awk '/ BUILT_PRODUCTS_DIR =/ {print $$3; exit}'); \
	APP=$$(echo "$$SETTINGS" | awk '/ FULL_PRODUCT_NAME =/ {print $$3; exit}'); \
	open "$$DIR/$$APP"

clean:
	rm -rf build/ DerivedData/
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
