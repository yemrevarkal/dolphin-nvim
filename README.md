# dolphin-nvim

Personal Neovim + Tmux + Alacritty + Kitty configuration, reproducible on any
Ubuntu machine (native / WSL / remote instance).

## Quick start

```bash
git clone https://github.com/yemrevarkal/dolphin-nvim.git ~/dolphin-nvim
cd ~/dolphin-nvim
./install.sh
```

Then open a new shell (so `nvim` is on `PATH`) and run `nvim` — that's it.

`install.sh` installs every dependency, symlinks the configs into `~/.config`,
clones TPM, and bootstraps plugins / LSP servers / treesitter parsers.
It is **idempotent** — safe to re-run — and must be run as your normal user
(it uses `sudo` only where system packages are needed).

### Flags

| Flag | Effect |
|------|--------|
| `--with-rust` | Install rustup + the musl target and build the jupynvim remote core binary (SSH-remote notebooks). |
| `--with-terminals` | Force-install the alacritty + kitty **binaries** even on WSL/headless. |
| `--skip-bootstrap` | Symlink + install deps only; don't launch Neovim/tmux to install plugins. |

By default the GUI terminal **binaries** (alacritty, kitty) are installed only
when a display is present and you're not on WSL. Their **configs are always
symlinked** regardless, so they're ready when you do use a GUI terminal.

To pin a specific Neovim version, set `NVIM_VERSION` (default `stable`):

```bash
NVIM_VERSION=v0.12.0 ./install.sh   # or "nightly"
```

## What it installs

- **apt:** build-essential, git, curl, ripgrep, fd-find (linked as `fd`), xclip,
  imagemagick, stow, python3 (+venv/pip), fontconfig
- **Node.js** (NodeSource LTS) + `tree-sitter-cli`
- **Neovim** from the official release tarball → `~/.local` (works on WSL/remote,
  where `snap` and `apt` fall short)
- **JetBrainsMono Nerd Font** → `~/.local/share/fonts`
- **GUI terminals** (auto/optional): kitty (official installer), alacritty (apt)
- **Symlinks** via GNU Stow: `nvim` `tmux` `alacritty` `kitty` → `~/.config/*`
- **TPM** → `~/.tmux/plugins/tpm`, plus first-run plugin install

## Treesitter parsers (important)

`nvim-treesitter` is pinned to its **`main`** branch, whose in-config auto-install
is unreliable — so parsers are compiled explicitly with the **`tree-sitter` CLI**,
which `install.sh` then drives via a headless `:TSInstall …`.

⚠️ **glibc gotcha:** the npm `tree-sitter-cli` ships a prebuilt binary linked
against a recent glibc (2.39 / Ubuntu 24.04). On **older Ubuntu** it fails at
runtime with `libc.so.6: version 'GLIBC_2.39' not found`, and parser compiles die
with `Error during "tree-sitter build"`. `install.sh` handles this: it installs the
npm CLI, tests that it actually runs, and if not, **builds the CLI from source with
`cargo install tree-sitter-cli`** (links against the local glibc — works on any
Ubuntu).

If syntax colors are still missing, verify and install manually:

```bash
tree-sitter --version    # must print a version, NOT a GLIBC error
# if it errors: cargo install tree-sitter-cli   (installs to ~/.cargo/bin)
```

```vim
:TSInstall python rust lua javascript typescript c bash markdown markdown_inline vimdoc
```

Also ensure a C compiler is present (`build-essential`).

## Notes

- **Config portability:** the Neovim Python host is resolved at runtime from
  `$CONDA_PREFIX` → `$VIRTUAL_ENV` → `python3` (`nvim/lua/locusted/lazy_init.lua`),
  so nothing is hardcoded to a machine — activate a conda env / venv before
  launching `nvim` and the correct interpreter is used for LSP, REPL, and DAP.
- **Inline plots inside tmux:** jupynvim renders notebook images via the kitty
  graphics protocol, which tmux drops unless passthrough is enabled. The bundled
  `tmux/tmux.conf` sets `allow-passthrough on`; after the first install run
  `tmux source ~/.config/tmux/tmux.conf` (or restart the tmux server) so plots
  render in kitty.
- **Alacritty from apt** may be older than the 0.16+ the config targets; if
  features are missing, install a newer build (e.g. `cargo install alacritty`).

## jupynvim remote (SSH cluster)

jupynvim's remote feature runs its Rust backend (`jupynvim-core`) on the cluster.
You build a static Linux binary **locally** and jupynvim uploads it over SSH on
connect — nothing needs to be installed on the remote.

`./install.sh --with-rust` does the one-time setup (rustup + musl target + first
build). To rebuild after a plugin update:

```bash
source ~/.cargo/env
cd ~/.local/share/nvim/lazy/jupynvim/core
cargo build --release --target x86_64-unknown-linux-musl
```

Then connect from Neovim (`mmm` is a `~/.ssh/config` Host alias):

```vim
:JupynvimConnect mmm
:JupynvimOpenRemote mmm:~/path/to/notebook.ipynb
```

> The plugin's `:JupynvimCrossBuild` does the same build from inside Neovim but
> requires `zig`; the `cargo build` above is simpler when host and cluster are
> both x86_64 Linux.
