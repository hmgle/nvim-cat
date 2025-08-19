# Makefile for nvim-cat
# A syntax-highlighted file viewer powered by Neovim

.PHONY: install uninstall clean help

# Default installation directories
PREFIX ?= /usr/local
BINDIR = $(PREFIX)/bin
SHAREDIR = $(PREFIX)/share/nvim-cat

# Get the absolute path of the project directory
PROJECT_DIR := $(shell pwd)

help:
	@echo "nvim-cat - Syntax-highlighted file viewer powered by Neovim"
	@echo ""
	@echo "Available targets:"
	@echo "  install     Install nvim-cat to system (requires sudo for system-wide install)"
	@echo "  install-user Install nvim-cat to user directory (~/.local/bin)"
	@echo "  uninstall   Uninstall nvim-cat from system"
	@echo "  uninstall-user Uninstall nvim-cat from user directory"
	@echo "  clean       Clean temporary files"
	@echo "  help        Show this help message"
	@echo ""
	@echo "Installation options:"
	@echo "  make install                    # Install system-wide (requires sudo)"
	@echo "  make install-user               # Install to ~/.local/bin (recommended)"
	@echo "  make install PREFIX=/opt/local  # Install to custom prefix"

install: check-nvim
	@echo "Installing nvim-cat to $(BINDIR)..."
	install -d $(BINDIR)
	install -d $(SHAREDIR)
	install -m 755 bin/nvim-cat $(BINDIR)/nvim-cat
	cp -r lua $(SHAREDIR)/
	@echo ""
	@echo "✅ nvim-cat installed successfully!"
	@echo "   Binary: $(BINDIR)/nvim-cat"
	@echo "   Lua modules: $(SHAREDIR)/lua"
	@echo ""
	@echo "You can now use: nvim-cat <file>"

install-user: check-nvim
	@echo "Installing nvim-cat to ~/.local/bin..."
	install -d ~/.local/bin
	install -d ~/.local/share/nvim-cat
	install -m 755 bin/nvim-cat ~/.local/bin/nvim-cat
	cp -r lua ~/.local/share/nvim-cat/
	# Update the script to use the user installation path
	sed -i.bak 's|script_dir/lua|~/.local/share/nvim-cat/lua|g' ~/.local/bin/nvim-cat
	rm ~/.local/bin/nvim-cat.bak
	@echo ""
	@echo "✅ nvim-cat installed successfully!"
	@echo "   Binary: ~/.local/bin/nvim-cat"
	@echo "   Lua modules: ~/.local/share/nvim-cat/lua"
	@echo ""
	@echo "Make sure ~/.local/bin is in your PATH:"
	@echo "   echo 'export PATH=\"\$$PATH:\$$HOME/.local/bin\"' >> ~/.bashrc"
	@echo "   source ~/.bashrc"
	@echo ""
	@echo "You can now use: nvim-cat <file>"

uninstall:
	@echo "Uninstalling nvim-cat from $(BINDIR)..."
	rm -f $(BINDIR)/nvim-cat
	rm -rf $(SHAREDIR)
	@echo "✅ nvim-cat uninstalled successfully!"

uninstall-user:
	@echo "Uninstalling nvim-cat from ~/.local/bin..."
	rm -f ~/.local/bin/nvim-cat
	rm -rf ~/.local/share/nvim-cat
	@echo "✅ nvim-cat uninstalled successfully!"

check-nvim:
	@echo "Checking Neovim installation..."
	@which nvim > /dev/null || (echo "❌ Error: Neovim is not installed or not in PATH" && exit 1)
	@nvim --version | head -1
	@echo "✅ Neovim found"

clean:
	@echo "Cleaning temporary files..."
	find . -name "*.tmp" -delete
	find . -name "*~" -delete
	find . -name ".#*" -delete
	@echo "✅ Cleanup complete!"

# Development targets
dev-install: install-user
	@echo "Development installation complete!"
	@echo "You can edit the source code and changes will be reflected immediately."

dev-uninstall: uninstall-user
