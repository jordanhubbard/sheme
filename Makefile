# Detect user's shell before overriding SHELL for Make recipes
USER_SHELL := $(shell echo $$SHELL)
SHELL_TYPE ?= $(if $(findstring zsh,$(USER_SHELL)),zsh,bash)

ifeq ($(SHELL_TYPE),zsh)
  RCFILE ?= $(HOME)/.zshrc
else
  RCFILE ?= $(HOME)/.bashrc
endif

SCRIPT := $(abspath bad-scheme.sh)

SHELL := /bin/bash

.PHONY: install uninstall check test example

install:
	@echo "Detected shell: $(SHELL_TYPE) (override with SHELL_TYPE=bash|zsh)"
	@if ! grep -q 'source.*bad-scheme' "$(RCFILE)" 2>/dev/null; then \
		echo '' >> "$(RCFILE)"; \
		echo '# bad-scheme - Scheme interpreter as shell functions' >> "$(RCFILE)"; \
		echo 'source "$(SCRIPT)"' >> "$(RCFILE)"; \
		echo "Added source line to $(RCFILE)"; \
	else \
		echo "$(RCFILE) already sources bad-scheme"; \
	fi
	@echo "Installed. Open a new shell or: source $(RCFILE)"

uninstall:
	@if [ -f "$(RCFILE)" ]; then \
		sed -i '' '/# bad-scheme/d; /source.*bad-scheme/d' "$(RCFILE)"; \
		echo "Removed from $(RCFILE)"; \
	fi
	@echo "Uninstalled."

check:
	@echo "Checking syntax..."
	@bash -n bad-scheme.sh && echo "  bad-scheme.sh: Syntax OK"

test: check
	@bats tests/bad-scheme.bats

example: check
	@bash examples/demo.sh
