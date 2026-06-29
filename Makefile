SHELL      := /bin/bash
SRCDIR     := $(abspath .)
BUMP       ?= patch

.DEFAULT_GOAL := help

.PHONY: install uninstall check test test-compiler test-io test-r5rs \
        test-examples test-all \
        benchmark example example-bash example-zsh algorithms channels repl \
        todo release help

help: ## Show available make targets
	@awk 'BEGIN {FS = ":.*##"}; /^[a-zA-Z0-9_-]+:.*##/ { printf "  %-20s %s\n", $$1, $$2 }' \
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

test: check ## Run Bash, zsh, and AOT compiler test suites
	@echo ""
	@echo "── Bash tests ──"
	@bats tests/bs.bats
	@echo ""
	@echo "── Zsh tests ──"
	@zsh tests/bs-zsh.zsh
	@echo ""
	@echo "── AOT compiler tests ──"
	@bash tests/compiler-tests.sh

test-compiler: check ## Run Bash/zsh AOT compiler regression tests
	@bash tests/compiler-tests.sh

test-io: ## Run dedicated Bash I/O tests (zsh I/O is covered by make test)
	@echo ""
	@echo "── Dedicated Bash I/O builtin tests ──"
	@bash tests/io-tests.sh

test-r5rs: ## Run R5RS-subset checks against the Bash interpreter
	@echo ""
	@echo "── R5RS compatibility tests ──"
	@bash tests/r5rs-tests.sh

test-examples: check ## Run non-interactive regressions for larger examples
	@bash tests/examples-tests.sh

test-all: test test-io test-r5rs test-examples ## Run every test suite

benchmark: ## Run performance benchmarks
	@bash tests/benchmark.sh

example: example-bash example-zsh ## Run maintained Bash and zsh showcases

example-bash: check ## Run the Bash-hosted feature showcase
	@bash examples/demo.sh

example-zsh: check ## Run the zsh-hosted feature showcase
	@zsh examples/demo.zsh

algorithms: check ## Run maintained algorithmic examples
	@bash examples/algorithms.sh

channels: check ## Run maintained shell-pipeline examples
	@bash examples/channels.sh

repl: check ## Launch the interactive REPL
	@bash examples/repl.sh

todo: check ## Show the task-manager example
	@bash examples/todo.sh

release: ## Create a release: make release BUMP=patch|minor|major
	@bash scripts/release.sh $(BUMP)
