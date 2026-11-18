.PHONY: help build test check tokens app run snapshot identity sign-identity install uninstall update mirror skills clean

help:              ## this list
	@grep -E '^[a-z-]+:.*##' $(MAKEFILE_LIST) | awk -F':.*##' '{printf "  %-10s %s\n", $$1, $$2}'

build:             ## debug build with the command-line tools
	swift build

test:              ## the tests
	swift test

check: test        ## tests, Tokens.swift agrees with ds-cli-design's tokens.json, and the tools-only build
	python3 scripts/gen_tokens.py --check
	DEVELOPER_DIR=/Library/Developer/CommandLineTools swift build --scratch-path .build-clt

tokens:            ## regenerate Tokens.swift from ds-cli-design's tokens.json
	python3 scripts/gen_tokens.py

app:               ## release build wrapped as build/the-great-gui.app (SIGN_IDENTITY=… for a stable signature)
	scripts/bundle.sh

run: app           ## build the app and open it
	open build/the-great-gui.app

snapshot:          ## draw the window's screens to build/snapshots/*.png, both themes, light and dark
	swift run GreatGUI --snapshot build/snapshots

install: sign-identity app skills ## a signing identity for this Mac, then build the app; link great-gui into ~/.local/bin, the skills into the agents, the app into ~/Applications
	mkdir -p $(HOME)/.local/bin && ln -sfn "$(CURDIR)/bin/great-gui" $(HOME)/.local/bin/great-gui
	@echo "✓ great-gui  $(HOME)/.local/bin/great-gui → $(CURDIR)/bin/great-gui"
	mkdir -p $(HOME)/Applications && ln -sfn "$(CURDIR)/build/the-great-gui.app" $(HOME)/Applications/the-great-gui.app
	@echo "✓ app        $(HOME)/Applications/the-great-gui.app → build/the-great-gui.app · Spotlight finds it"

update:            ## pull this checkout, rebuild and relink (install), and reopen the app if it was running
	scripts/update.sh

mirror:            ## copy this checkout to a second git host (TO=ADDRESS the first time), for teammates to install from
	@scripts/mirror.sh $(TO)

uninstall:         ## unlink great-gui, the skills and the Applications link (the app bundle and your registry stay)
	@[ -L $(HOME)/.local/bin/great-gui ] && unlink $(HOME)/.local/bin/great-gui && echo "  removed ~/.local/bin/great-gui" || true
	@[ -L $(HOME)/Applications/the-great-gui.app ] && unlink $(HOME)/Applications/the-great-gui.app && echo "  removed ~/Applications/the-great-gui.app" || true
	scripts/install-skills.sh --uninstall

skills:            ## link skills/* into the Claude, Codex, Hermes and Cortex skill folders that exist
	scripts/install-skills.sh

identity:          ## the code-signing certificates this Mac has, and which one .sign-identity names
	@security find-identity -p codesigning | sed 's/^/  /'
	@scripts/identity.sh --check

sign-identity:     ## make sure this Mac has a signing identity (self-signed, made here, nothing from Apple) and name it in .sign-identity
	@scripts/identity.sh

clean:             ## remove build products
	rm -rf .build .build-clt build
