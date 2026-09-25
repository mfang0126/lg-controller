SHELL := /bin/sh

PROJECT := LGVolumeRouter.xcodeproj
SCHEME := LGVolumeRouter
CONFIGURATION ?= Release
DERIVED_DATA ?= build
APP_PATH := $(DERIVED_DATA)/Build/Products/$(CONFIGURATION)/LGVolumeRouter.app
CLI_PATH := $(DERIVED_DATA)/lg-volume
CLI_SOURCES := \
	tools/lg-volume.swift \
	LGVolumeRouter/ProductConfiguration.swift \
	LGVolumeRouter/WebOSMessage.swift \
	LGVolumeRouter/KeychainStore.swift
TEST_BINARY := $(DERIVED_DATA)/policy-tests
TEST_SOURCES := \
	LGVolumeRouter/RoutingPolicy.swift \
	tests/RoutingPolicyTests.swift

.PHONY: all app cli test run-app clean help

all: app cli

## Build an unsigned local App bundle. Use your own Developer ID workflow for distribution.
app:
	xcodebuild \
		-project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration "$(CONFIGURATION)" \
		-sdk macosx \
		-derivedDataPath "$(DERIVED_DATA)" \
		CODE_SIGNING_ALLOWED=NO \
		build

## Build the standalone macOS command-line client.
cli:
	mkdir -p "$(DERIVED_DATA)"
	xcrun swiftc -O -o "$(CLI_PATH)" $(CLI_SOURCES)

## Run the routing-decision matrix tests (swiftc direct; no Xcode test target).
test:
	mkdir -p "$(DERIVED_DATA)"
	xcrun swiftc -o "$(TEST_BINARY)" $(TEST_SOURCES)
	"$(TEST_BINARY)"

run-app: app
	open "$(APP_PATH)"

clean:
	rm -rf "$(DERIVED_DATA)"

help:
	@printf '%s\n' 'Targets: all, app, cli, test, run-app, clean'
