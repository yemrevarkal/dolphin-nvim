# dolphin-nvim

Personal Neovim + Tmux + Alacritty configuration.

## Requirements

- [ripgrep](https://github.com/BurntSushi/ripgrep#installation) — required by Telescope for live grep
- [Node.js](https://nodejs.org/) — required by Mason for some LSP server installations
- [tree-sitter-cli](https://github.com/tree-sitter/tree-sitter/blob/master/cli/README.md) — required by nvim-treesitter to compile parsers (`npm install -g tree-sitter-cli`)
- [Alacritty](https://alacritty.org/) (0.16+) — GPU-accelerated terminal emulator
- [kitty](https://sw.kovidgoyal.net/kitty/) — GPU-accelerated terminal with keyboard protocol + image rendering
- [ImageMagick](https://imagemagick.org/) — used by jupynvim to convert non-PNG inline notebook images to PNG (`sudo apt install imagemagick`)
- [JetBrainsMono Nerd Font](https://www.nerdfonts.com/font-downloads) — for icons in statusline and file explorer
- [GNU Stow](https://www.gnu.org/software/stow/) — for symlinking configs
- [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm#installation) — for tmux plugins

> **Inline plots inside tmux:** jupynvim renders notebook images via the Kitty
> graphics protocol, which tmux drops unless passthrough is enabled. The bundled
> `tmux/tmux.conf` sets `allow-passthrough on`; reload it (`tmux source ~/.config/tmux/tmux.conf`)
> or restart the tmux server after first stow so plots render in kitty.

## Setup

### Install JetBrainsMono Nerd Font

```bash
mkdir -p ~/.local/share/fonts
cd ~/.local/share/fonts
curl -fLO https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip
unzip JetBrainsMono.zip -d JetBrainsMono
rm JetBrainsMono.zip
fc-cache -fv
```

### Symlink configs

```bash
git clone https://github.com/yemrevarkal/dolphin-nvim.git ~/dolphin-nvim
cd ~/dolphin-nvim
stow -t ~/.config/nvim nvim
stow -t ~/.config/tmux tmux
stow -t ~/.config/alacritty alacritty
stow -t ~/.config/kitty kitty
```

### Install tree-sitter-cli

```bash
npm install -g tree-sitter-cli
```

Open Neovim and Lazy will automatically install all plugins on first launch.

### Install treesitter parsers

```vim
:TSInstall python rust lua javascript typescript c bash markdown markdown_inline vimdoc
```

### jupynvim remote (SSH cluster)

jupynvim's remote feature runs its Rust backend (`jupynvim-core`) on the cluster.
You build a static Linux binary **locally**, and jupynvim uploads it over SSH on
connect — nothing needs to be installed on the remote.

One-time setup (local machine):

```bash
# rustup + the static-musl target (skip if already installed)
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup target add x86_64-unknown-linux-musl

# build the binary jupynvim uploads to the remote
cd ~/.local/share/nvim/lazy/jupynvim/core
cargo build --release --target x86_64-unknown-linux-musl
```

Then connect from Neovim (`mmm` is an `~/.ssh/config` Host alias):

```vim
:JupynvimConnect mmm
:JupynvimOpenRemote mmm:~/path/to/notebook.ipynb
```

> **Rebuilding:** re-run the `cargo build` command above after a plugin update.
> It needs `~/.cargo/bin` on `PATH` (a fresh terminal has it; otherwise
> `source ~/.cargo/env`). The plugin's `:JupynvimCrossBuild` does the same build
> from inside Neovim but requires `zig`, so the `cargo build` command is simpler.
> No `zig` is needed here because the host and cluster are both x86_64 Linux.
