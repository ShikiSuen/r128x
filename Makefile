SHELL := /bin/sh

# 定义日期和时间变量
DATE_DIR := $(shell date +%Y-%m-%d)
DATE_FILE := $(shell date +%Y-%-m-%-d)
TIME_FILE := $(shell date +%H.%M)
ARCHIVE_DIR := $(HOME)/Library/Developer/Xcode/Archives/$(DATE_DIR)
ARCHIVE_NAME := ThePizzaHelper-$(DATE_FILE)-$(TIME_FILE).xcarchive
ARCHIVE_PATH := $(ARCHIVE_DIR)/$(ARCHIVE_NAME)

.PHONY: format lint

format:
	@swiftformat --swiftversion 5.7 ./

lint:
	@git ls-files --exclude-standard | grep -E '\.swift$$' | swiftlint --fix --autocorrect

archive: archive-macOS archive-iOS

archive-iOS:
	@ARCHIVE_NAME=r128x-swiftui-iOS-$(DATE_FILE)-$(TIME_FILE).xcarchive; \
	ARCHIVE_PATH=$(ARCHIVE_DIR)/$$ARCHIVE_NAME; \
	echo "Creating directory: $(ARCHIVE_DIR)"; \
	mkdir -p "$(ARCHIVE_DIR)"; \
	echo "Archiving to: $$ARCHIVE_PATH"; \
	xcodebuild archive \
		-project r128x.xcodeproj \
		-scheme r128x-swiftui \
		-configuration Release \
		-destination "generic/platform=iOS" \
		-archivePath "$$ARCHIVE_PATH" \
		-allowProvisioningUpdates

archive-macOS:
	@ARCHIVE_NAME=r128x-swiftui-macOS-$(DATE_FILE)-$(TIME_FILE).xcarchive; \
	ARCHIVE_PATH=$(ARCHIVE_DIR)/$$ARCHIVE_NAME; \
	echo "Creating directory: $(ARCHIVE_DIR)"; \
	mkdir -p "$(ARCHIVE_DIR)"; \
	echo "Archiving to: $$ARCHIVE_PATH"; \
	xcodebuild archive \
		-project r128x.xcodeproj \
		-scheme r128x-swiftui \
		-configuration Release \
		-destination "generic/platform=macOS" \
		-archivePath "$$ARCHIVE_PATH" \
		-allowProvisioningUpdates
