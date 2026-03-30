# dolphin-nvim

Personal Neovim + Tmux + Alacritty configuration.

## Requirements

- [ripgrep](https://github.com/BurntSushi/ripgrep#installation) — required by Telescope for live grep
- [Node.js](https://nodejs.org/) — required by Mason for some LSP server installations
- [Alacritty](https://alacritty.org/) (0.16+) — GPU-accelerated terminal emulator
- [JetBrainsMono Nerd Font](https://www.nerdfonts.com/font-downloads) — for icons in statusline and file explorer
- [GNU Stow](https://www.gnu.org/software/stow/) — for symlinking configs
- [TPM (Tmux Plugin Manager)](https://github.com/tmux-plugins/tpm#installation) — for tmux plugins

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
```

Open Neovim and Lazy will automatically install all plugins on first launch.
