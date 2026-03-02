SHELL      := /bin/bash
SRCDIR     := $(abspath .)
BUMP       ?= patch

.DEFAULT_GOAL := help

.PHONY: install uninstall check test test-io test-r5rs test-all benchmark \
        example algorithms channels repl todo release help

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' \
	  $(MAKEFILE_LIST)

install: ## Install bs.sh and bs.zsh to home directory
	@echo "Installing sheme to home directory..."
	@cp "$(SRCDIR)/bs.sh" "$(HOME)/.bs.sh"
	@cp "$(SRCDIR)/bs.zsh" "$(HOME)/.bs.zsh"
	@echo "Installed ~/.bs.sh and ~/.bs.zsh"
	@if ! grep -q '# sheme install marker' "$(HOME)/.bashrc" 2>/dev/null; then \
		echo '' >> "$(HOME)/.bashrc"; \
		echo '# sheme install marker' >> "$(HOME)/.bashrc"; \
		echo '[[ -f "$$HOME/.bs.sh" ]] && source "$$HOME/.bs.sh"' >> "$(HOME)/.bashrc"; \
		echo "Added source line to ~/.bashrc"; \
	else \
		echo "~/.bashrc already has sheme installed"; \
	fi
	@if ! grep -q '# sheme install marker' "$(HOME)/.zshrc" 2>/dev/null; then \
		echo '' >> "$(HOME)/.zshrc"; \
		echo '# sheme install marker' >> "$(HOME)/.zshrc"; \
		echo '[[ -f "$$HOME/.bs.zsh" ]] && source "$$HOME/.bs.zsh"' >> "$(HOME)/.zshrc"; \
		echo "Added source line to ~/.zshrc"; \
	else \
		echo "~/.zshrc already has sheme installed"; \
	fi
	@echo "Installed. Open a new shell or source your rc file."

uninstall: ## Remove sheme from home directory
	@rm -f "$(HOME)/.bs.sh" "$(HOME)/.bs.zsh"
	@[ -f "$(HOME)/.bashrc" ] && sed -i '' '/# sheme install marker/d; /# bad-scheme/d; /# sheme -/d; /source.*\.bs\.sh/d; /sourceif.*\.bs\.sh/d; /\[.*\.bs\.sh.*\] && source/d' "$(HOME)/.bashrc" 2>/dev/null || \
		sed -i '/# sheme install marker/d; /# bad-scheme/d; /# sheme -/d; /source.*\.bs\.sh/d; /sourceif.*\.bs\.sh/d; /\[.*\.bs\.sh.*\] && source/d' "$(HOME)/.bashrc" 2>/dev/null || true
	@[ -f "$(HOME)/.zshrc" ] && sed -i '' '/# sheme install marker/d; /# bad-scheme/d; /# sheme -/d; /source.*\.bs\.zsh/d; /sourceif.*\.bs\.zsh/d; /\[.*\.bs\.zsh.*\] && source/d' "$(HOME)/.zshrc" 2>/dev/null || \
		sed -i '/# sheme install marker/d; /# bad-scheme/d; /# sheme -/d; /source.*\.bs\.zsh/d; /sourceif.*\.bs\.zsh/d; /\[.*\.bs\.zsh.*\] && source/d' "$(HOME)/.zshrc" 2>/dev/null || true
	@echo "Uninstalled sheme."

check: ## Validate shell syntax without running tests
	@echo "Checking syntax..."
	@bash -n bs.sh && echo "  bs.sh:  Syntax OK"
	@zsh -n bs.zsh && echo "  bs.zsh: Syntax OK"

test: check ## Run bash (BATS) and zsh test suites
	@echo ""
	@echo "── Bash tests ──"
	@bats tests/bs.bats
	@echo ""
	@echo "── Zsh tests ──"
	@zsh tests/bs-zsh.zsh

test-io: ## Run terminal I/O builtin tests (bash only)
	@echo ""
	@echo "── I/O builtin tests (bash only) ──"
	@bash tests/io-tests.sh

test-r5rs: ## Run R5RS compatibility tests
	@echo ""
	@echo "── R5RS compatibility tests ──"
	@bash tests/r5rs-tests.sh

test-all: test test-io test-r5rs ## Run all test suites (bash, zsh, R5RS, I/O)

benchmark: ## Run performance benchmarks
	@bash tests/benchmark.sh

example: check ## Run the feature showcase demo
	@bash examples/demo.sh

algorithms: check ## Run algorithmic examples
	@bash examples/algorithms.sh

channels: check ## Run concurrency pattern examples
	@bash examples/channels.sh

repl: check ## Launch the interactive REPL
	@bash examples/repl.sh

todo: check ## Launch the todo manager (usage shown)
	@bash examples/todo.sh

release: ## Create a release: make release BUMP=patch|minor|major
	@bash scripts/release.sh $(BUMP)
