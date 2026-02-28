# Detect user's shell before overriding SHELL for Make recipes
USER_SHELL := $(shell echo $$SHELL)
SHELL_TYPE ?= $(if $(findstring zsh,$(USER_SHELL)),zsh,bash)

ifeq ($(SHELL_TYPE),zsh)
  RCFILE ?= $(HOME)/.zshrc
  SCRIPT := $(abspath bad-scheme.zsh)
else
  RCFILE ?= $(HOME)/.bashrc
  SCRIPT := $(abspath bad-scheme.sh)
endif

SHELL := /bin/bash
PREFIX ?= /usr/local
SRCDIR := $(abspath .)

.PHONY: install install-em uninstall uninstall-em check test test-em test-all benchmark example

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

install-em: install
	@echo ""
	@echo "Installing em (Scheme-powered Emacs-like editor)..."
	@mkdir -p "$(PREFIX)/bin"
	@ln -sf "$(SRCDIR)/bin/em" "$(PREFIX)/bin/em"
	@echo "Installed em -> $(PREFIX)/bin/em"
	@echo "Run 'em [file]' to launch the editor."

uninstall:
	@if [ -f "$(RCFILE)" ]; then \
		sed -i '' '/# bad-scheme/d; /source.*bad-scheme/d' "$(RCFILE)"; \
		echo "Removed from $(RCFILE)"; \
	fi
	@echo "Uninstalled."

uninstall-em:
	@rm -f "$(PREFIX)/bin/em"
	@echo "Removed $(PREFIX)/bin/em"

check:
	@echo "Checking syntax..."
	@bash -n bad-scheme.sh && echo "  bad-scheme.sh:  Syntax OK"
	@zsh -n bad-scheme.zsh && echo "  bad-scheme.zsh: Syntax OK"

test: check
	@echo ""
	@echo "── Bash tests ──"
	@bats tests/bad-scheme.bats
	@echo ""
	@echo "── Zsh tests ──"
	@zsh tests/bad-scheme-zsh.zsh

test-em:
	@echo ""
	@echo "── Scheme editor tests ──"
	@bash tests/run_em_tests.sh

test-all: test test-em

benchmark:
	@bash tests/benchmark.sh

example: check
	@bash examples/demo.sh
