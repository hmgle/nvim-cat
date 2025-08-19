# nvim-cat

A syntax-highlighted file viewer for the command line, similar to `bat` and `ccat`, but powered by Neovim's built-in syntax highlighting engine.

## Features

- **True Neovim Integration**: Uses your actual Neovim colorscheme and highlight groups
- **24-bit True Color**: Supports 16 million colors for precise color reproduction
- **Multi-filetype Support**: Automatic file type detection and appropriate syntax highlighting
- **Line Numbers**: Optional line number display
- **Colorscheme Support**: Auto-detects and loads your Neovim colorscheme
- **Paging**: Automatic paging for long files
- **Fast**: Built with Lua for optimal performance
- **Smart Fallback**: Graceful degradation from True Color → 256 → 16 colors

## Why nvim-cat?

Unlike other syntax highlighters that use their own highlighting rules, nvim-cat leverages Neovim's powerful syntax highlighting engine. This means:

- **Consistent with your editor**: Colors match exactly what you see in Neovim
- **Comprehensive language support**: Supports any language that Neovim supports
- **Familiar colorschemes**: Use the same colorschemes you love in your editor
- **TreeSitter ready**: Future support for TreeSitter-based highlighting

## Requirements

- Neovim 0.10+
- Bash (for the command-line wrapper)

## Installation

### Quick Install (Recommended)

#### Option 1: Using the install script

```bash
# Clone and install in one go
git clone https://github.com/hmgle/nvim-cat.git
cd nvim-cat
./install.sh

# The script will guide you through the installation
```

#### Option 2: Using Make

```bash
# Clone the repository
git clone https://github.com/hmgle/nvim-cat.git
cd nvim-cat

# Install for current user (no sudo required)
make install-user

# Add ~/.local/bin to your PATH if not already there
echo 'export PATH="$PATH:$HOME/.local/bin"' >> ~/.bashrc
source ~/.bashrc
```

### System-wide Installation

```bash
git clone https://github.com/hmgle/nvim-cat.git
cd nvim-cat

# Option 1: Using install script
./install.sh --system

# Option 2: Using Make
sudo make install

# Option 3: Custom prefix
./install.sh --prefix /opt
# or
make install PREFIX=/opt
```

### Development Installation

```bash
git clone https://github.com/hmgle/nvim-cat.git
cd nvim-cat

# Use directly from source (no installation)
./bin/nvim-cat file.lua

# Or install for development
make dev-install
```

## Usage

### Basic Usage

```bash
# View a single file
nvim-cat file.lua

# View multiple files
nvim-cat *.js

# View with specific options
nvim-cat --no-line-numbers --theme dark file.py
```

### Command Line Options

```bash
nvim-cat [OPTIONS] <FILE|PATTERN>...

OPTIONS:
    -n, --line-numbers      Show line numbers (default: true)
    -N, --no-line-numbers   Hide line numbers
    -p, --paging            Enable paging (default: true)
    -P, --no-paging         Disable paging
    -l, --lines-per-page N  Lines per page (default: 50)
    -t, --theme THEME       Color theme (auto, dark, light)
    -c, --colorscheme NAME  Neovim colorscheme to use
    -b, --background        Use global background color (default: true)
    -B, --no-background     Disable global background color
    -H, --header           Show file header
    -h, --help             Show this help
    -v, --version          Show version
```

### Examples

```bash
# Basic file viewing
nvim-cat src/main.lua
nvim-cat README.md

# Multiple files
nvim-cat src/*.lua

# Custom options
nvim-cat --no-line-numbers config.json
nvim-cat --no-paging --theme light script.js
nvim-cat --colorscheme gruvbox --no-background file.rs

# Large files (with paging)
nvim-cat --lines-per-page 30 large_file.log
```

## Uninstallation

```bash
# Using install script
./install.sh --uninstall

# Using Make
make uninstall-user          # for user installation
sudo make uninstall          # for system installation

# Manual cleanup if needed
rm -f ~/.local/bin/nvim-cat
rm -rf ~/.local/share/nvim-cat
```

## Configuration

nvim-cat can be configured via command-line options or environment variables:

### Environment Variables

```bash
# Set default colorscheme
export NVIM_CAT_COLORSCHEME="gruvbox"

# Set default theme
export NVIM_CAT_THEME="dark"

# Disable line numbers by default
export NVIM_CAT_LINE_NUMBERS="false"

# Disable paging by default
export NVIM_CAT_PAGING="false"
```

### Neovim Configuration

If you want to customize colorschemes or add new file types, you can do so through your Neovim configuration, since nvim-cat uses Neovim's highlighting engine.

### Advanced Configuration

For advanced users, you can modify the Lua modules directly after installation:

```bash
# User installation
~/.local/share/nvim-cat/lua/nvim-cat/config.lua

# System installation
/usr/local/share/nvim-cat/lua/nvim-cat/config.lua
```

## License

MIT License - see [LICENSE](LICENSE) file for details.
