# 7-Zip Mac App - Build Makefile
#
# Usage:
#   make setup      - First-time setup (build 7zz + generate Xcode project)
#   make build-7zz  - Build the 7zz command-line binary for ARM64
#   make generate   - Generate Xcode project from project.yml
#   make build      - Build the app using xcodebuild
#   make run        - Build and run the app
#   make archive    - Create a release archive (.app bundle)
#   make dmg        - Create a DMG installer for distribution
#   make install-qa - Install Finder Quick Actions
#   make clean      - Clean build artifacts
#   make help       - Show this help
#

SHELL := /bin/bash
.DEFAULT_GOAL := help

SCHEME := SevenZipMac
PROJECT := SevenZipMac.xcodeproj
BUILD_DIR := build
ARCH := arm64

# ── Setup ────────────────────────────────────────────────────────

.PHONY: setup
setup: build-7zz generate ## First-time setup (build 7zz + generate project)
	@echo ""
	@echo "Setup complete! Open $(PROJECT) in Xcode or run 'make build'."

# ── Build 7zz ───────────────────────────────────────────────────

.PHONY: build-7zz
build-7zz: ## Build 7zz binary for ARM64 Mac
	@echo "=== Building 7zz binary ==="
	./Scripts/build_7zz.sh $(ARCH) $(BUILD_DIR)
	@mkdir -p SevenZipMac/Resources
	@cp $(BUILD_DIR)/7zz SevenZipMac/Resources/7zz
	@echo "7zz binary ready."

# ── Generate Xcode Project ──────────────────────────────────────

.PHONY: generate
generate: ## Generate Xcode project from project.yml
	@if command -v xcodegen &>/dev/null; then \
		echo "=== Generating Xcode project ===" ; \
		xcodegen generate ; \
	else \
		echo "XcodeGen not found. Install with: brew install xcodegen" ; \
		echo "Then run: make generate" ; \
		exit 1 ; \
	fi

# ── Build ────────────────────────────────────────────────────────

.PHONY: build
build: ## Build the app using xcodebuild
	@echo "=== Building $(SCHEME) ==="
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Debug \
		-arch $(ARCH) \
		ONLY_ACTIVE_ARCH=YES \
		| tail -20

.PHONY: build-release
build-release: ## Build release version
	@echo "=== Building $(SCHEME) (Release) ==="
	xcodebuild build \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-arch $(ARCH) \
		| tail -20

# ── Run ──────────────────────────────────────────────────────────

.PHONY: run
run: build ## Build and run the app
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Debug -showBuildSettings 2>/dev/null \
		| grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $$NF}') ; \
	open "$$APP_PATH/7-Zip.app"

# ── Archive ──────────────────────────────────────────────────────

.PHONY: archive
archive: ## Create release archive
	@echo "=== Archiving $(SCHEME) ==="
	@mkdir -p $(BUILD_DIR)/archive
	xcodebuild archive \
		-project $(PROJECT) \
		-scheme $(SCHEME) \
		-configuration Release \
		-archivePath $(BUILD_DIR)/archive/SevenZipMac.xcarchive \
		-arch $(ARCH)
	@echo "Archive created at $(BUILD_DIR)/archive/SevenZipMac.xcarchive"

# ── DMG Installer ───────────────────────────────────────────────

.PHONY: dmg
dmg: build-release ## Create DMG installer for distribution
	@echo "=== Creating DMG ==="
	@APP_PATH=$$(xcodebuild -project $(PROJECT) -scheme $(SCHEME) \
		-configuration Release -showBuildSettings 2>/dev/null \
		| grep " BUILT_PRODUCTS_DIR" | head -1 | awk '{print $$NF}') ; \
	./Scripts/create_dmg.sh "$$APP_PATH/7-Zip.app" $(BUILD_DIR)

.PHONY: dmg-from-archive
dmg-from-archive: archive ## Create DMG from xcarchive (requires full Xcode)
	@echo "=== Creating DMG from archive ==="
	./Scripts/create_dmg.sh \
		"$(BUILD_DIR)/archive/SevenZipMac.xcarchive/Products/Applications/7-Zip.app" \
		$(BUILD_DIR)

# ── Quick Actions ────────────────────────────────────────────────

.PHONY: install-qa
install-qa: ## Install Finder Quick Actions (right-click menu)
	./QuickActions/install-quick-actions.sh

# ── Clean ────────────────────────────────────────────────────────

.PHONY: clean
clean: ## Clean build artifacts
	@echo "=== Cleaning ==="
	rm -rf $(BUILD_DIR)
	rm -rf DerivedData
	xcodebuild clean -project $(PROJECT) -scheme $(SCHEME) 2>/dev/null || true
	@echo "Clean."

# ── Help ─────────────────────────────────────────────────────────

.PHONY: help
help: ## Show this help
	@echo "7-Zip Mac App - Build Commands"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Quick start:"
	@echo "  make setup    → build 7zz binary + generate Xcode project"
	@echo "  make build    → build the app"
	@echo "  make run      → build and launch the app"
