SHELL := /bin/bash
SRCDIR := $(abspath .)

.PHONY: install install-em uninstall uninstall-em check test test-em test-r5rs test-all benchmark example

install:
	@echo "Installing bad-scheme to home directory..."
	@cp "$(SRCDIR)/bs.sh" "$(HOME)/.bs.sh"
	@cp "$(SRCDIR)/bs.zsh" "$(HOME)/.bs.zsh"
	@echo "Installed ~/.bs.sh and ~/.bs.zsh"
	@if ! grep -q 'source.*\.bs\.sh' "$(HOME)/.bashrc" 2>/dev/null; then \
		echo '' >> "$(HOME)/.bashrc"; \
		echo '# bad-scheme - Scheme interpreter as shell functions' >> "$(HOME)/.bashrc"; \
		echo 'source "$(HOME)/.bs.sh"' >> "$(HOME)/.bashrc"; \
		echo "Added source line to ~/.bashrc"; \
	else \
		echo "~/.bashrc already sources ~/.bs.sh"; \
	fi
	@if ! grep -q 'source.*\.bs\.zsh' "$(HOME)/.zshrc" 2>/dev/null; then \
		echo '' >> "$(HOME)/.zshrc"; \
		echo '# bad-scheme - Scheme interpreter as shell functions' >> "$(HOME)/.zshrc"; \
		echo 'source "$(HOME)/.bs.zsh"' >> "$(HOME)/.zshrc"; \
		echo "Added source line to ~/.zshrc"; \
	else \
		echo "~/.zshrc already sources ~/.bs.zsh"; \
	fi
	@echo "Installed. Open a new shell or source your rc file."

install-em: install
	@echo ""
	@echo "Installing em (Scheme-powered Emacs-like editor)..."
	@cp "$(SRCDIR)/examples/em.sh" "$(HOME)/.em.sh"
	@cp "$(SRCDIR)/examples/em.scm" "$(HOME)/.em.scm"
	@echo "Installed ~/.em.sh and ~/.em.scm"
	@if ! grep -q 'source.*\.em\.sh' "$(HOME)/.bashrc" 2>/dev/null; then \
		echo '' >> "$(HOME)/.bashrc"; \
		echo '# em - Scheme-powered Emacs-like editor' >> "$(HOME)/.bashrc"; \
		echo 'source "$(HOME)/.em.sh"' >> "$(HOME)/.bashrc"; \
		echo "Added source line to ~/.bashrc"; \
	else \
		echo "~/.bashrc already sources ~/.em.sh"; \
	fi
	@echo "Run 'em [file]' to launch the editor."

uninstall:
	@rm -f "$(HOME)/.bs.sh" "$(HOME)/.bs.zsh"
	@[ -f "$(HOME)/.bashrc" ] && sed -i '' '/# bad-scheme/d; /source.*\.bs\./d' "$(HOME)/.bashrc" || true
	@[ -f "$(HOME)/.zshrc" ] && sed -i '' '/# bad-scheme/d; /source.*\.bs\./d' "$(HOME)/.zshrc" || true
	@echo "Uninstalled bad-scheme."

uninstall-em:
	@rm -f "$(HOME)/.em.sh" "$(HOME)/.em.scm"
	@[ -f "$(HOME)/.bashrc" ] && sed -i '' '/# em - Scheme/d; /source.*\.em\.sh/d' "$(HOME)/.bashrc" || true
	@echo "Removed ~/.em.sh and ~/.em.scm"

check:
	@echo "Checking syntax..."
	@bash -n bs.sh && echo "  bs.sh:  Syntax OK"
	@zsh -n bs.zsh && echo "  bs.zsh: Syntax OK"

test: check
	@echo ""
	@echo "── Bash tests ──"
	@bats tests/bs.bats
	@echo ""
	@echo "── Zsh tests ──"
	@zsh tests/bs-zsh.zsh

test-em:
	@echo ""
	@echo "── Scheme editor tests ──"
	@bash tests/run_em_tests.sh

test-r5rs:
	@echo ""
	@echo "── R5RS compatibility tests ──"
	@bash tests/r5rs-tests.sh

test-all: test test-em test-r5rs

benchmark:
	@bash tests/benchmark.sh

example: check
	@bash examples/demo.sh
