PREFIX ?= /usr/local
APP_NAME := MyPomodoro
BIN_NAME := mypomodoro
BUILD_DIR := .build/release
DIST_DIR := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app

.PHONY: all build app install test clean

all: app

build:
	swift build -c release --disable-sandbox

app: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	cp "$(BUILD_DIR)/$(BIN_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(BIN_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	-codesign --force --deep --sign - "$(APP_BUNDLE)" 2>/dev/null || true

install: app
	install -d "$(PREFIX)/bin"
	install -m 755 "$(BUILD_DIR)/$(BIN_NAME)" "$(PREFIX)/bin/$(BIN_NAME)"
	rm -rf "$(PREFIX)/$(APP_NAME).app"
	cp -R "$(APP_BUNDLE)" "$(PREFIX)/$(APP_NAME).app"

test:
	swift test --disable-sandbox

clean:
	rm -rf .build "$(DIST_DIR)"
