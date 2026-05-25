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
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG) -showBuildSettings 2>/dev/null | awk '/BUILT_PRODUCTS_DIR/ {print $$3; exit}'); \
	open "$$APP_PATH/$(SCHEME).app"

clean:
	rm -rf build/ DerivedData/
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
