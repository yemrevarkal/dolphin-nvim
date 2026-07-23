#!/usr/bin/env bash
#
# dolphin-nvim installer — reproducible setup for Ubuntu (native / WSL / remote).
#
# Usage:
#   ./install.sh [--with-rust] [--with-terminals] [--skip-bootstrap]
#
# Flags:
#   --with-rust        Install rustup + musl target and build the jupynvim remote
#                      core binary (only needed for :JupynvimConnect over SSH).
#   --with-terminals   Force-install the GUI terminal binaries (alacritty, kitty)
#                      even on WSL/headless. By default they are installed only
#                      when a display is present and this is not WSL.
#   --skip-bootstrap   Do not launch Neovim/tmux to install plugins.
#
# Idempotent: safe to re-run. Do NOT run as root — it installs into your $HOME.

set -euo pipefail

# ---------------------------------------------------------------------------
# Version pins — bump these to upgrade.
# NVIM_VERSION accepts "stable", "nightly", or a tag like "v0.12.0".
# ---------------------------------------------------------------------------
NVIM_VERSION="${NVIM_VERSION:-stable}"
NERD_FONT="JetBrainsMono"

# Treesitter parsers to install synchronously (mirrors treesitter.lua ensure_installed).
TS_PARSERS="vimdoc javascript typescript c lua rust python bash markdown markdown_inline"

# ---------------------------------------------------------------------------
# Setup / helpers
# ---------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="$HOME/.config"

WITH_RUST=0
WITH_TERMINALS=0
SKIP_BOOTSTRAP=0

for arg in "$@"; do
    case "$arg" in
        --with-rust)       WITH_RUST=1 ;;
        --with-terminals)  WITH_TERMINALS=1 ;;
        --skip-bootstrap)  SKIP_BOOTSTRAP=1 ;;
        -h|--help)
            sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "Unknown flag: $arg" >&2; exit 1 ;;
    esac
done

# Colored logging
if [ -t 1 ]; then
    C_BLUE='\033[1;34m'; C_GREEN='\033[1;32m'; C_YELLOW='\033[1;33m'; C_RED='\033[1;31m'; C_OFF='\033[0m'
else
    C_BLUE=''; C_GREEN=''; C_YELLOW=''; C_RED=''; C_OFF=''
fi
step()  { echo -e "\n${C_BLUE}==>${C_OFF} $*"; }
info()  { echo -e "    $*"; }
ok()    { echo -e "    ${C_GREEN}✓${C_OFF} $*"; }
warn()  { echo -e "    ${C_YELLOW}!${C_OFF} $*"; }
die()   { echo -e "${C_RED}error:${C_OFF} $*" >&2; exit 1; }

# Notes collected during the run, printed in the final summary.
NOTES=()
note() { NOTES+=("$*"); }

[ "$(id -u)" -eq 0 ] && die "do not run as root; run as your normal user (it uses sudo where needed)."

# Environment detection
IS_WSL=0
if grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null; then IS_WSL=1; fi
HAS_DISPLAY=0
if [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then HAS_DISPLAY=1; fi

# Should we install GUI terminal binaries?
INSTALL_TERMINALS=0
if [ "$WITH_TERMINALS" -eq 1 ]; then
    INSTALL_TERMINALS=1
elif [ "$IS_WSL" -eq 0 ] && [ "$HAS_DISPLAY" -eq 1 ]; then
    INSTALL_TERMINALS=1
fi

mkdir -p "$LOCAL_BIN"
export PATH="$LOCAL_BIN:$PATH"

# Ensure ~/.local/bin is on PATH in future shells.
ensure_path_in_bashrc() {
    local rc="$HOME/.bashrc"
    if [ -f "$rc" ] && grep -q '\.local/bin' "$rc"; then return; fi
    {
        echo ''
        echo '# Added by dolphin-nvim install.sh'
        echo 'export PATH="$HOME/.local/bin:$PATH"'
    } >> "$rc"
    note "Added ~/.local/bin to PATH in ~/.bashrc — open a new shell or 'source ~/.bashrc'."
}

# Install rustup/cargo if not present, and put cargo on PATH for this run.
ensure_rust() {
    if ! command -v cargo >/dev/null 2>&1; then
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    fi
    # shellcheck disable=SC1091
    [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
    export PATH="$HOME/.cargo/bin:$PATH"
    command -v cargo >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
step "Detected environment"
# ---------------------------------------------------------------------------
info "repo:      $REPO_DIR"
info "WSL:       $([ "$IS_WSL" -eq 1 ] && echo yes || echo no)"
info "display:   $([ "$HAS_DISPLAY" -eq 1 ] && echo yes || echo no)"
info "terminals: $([ "$INSTALL_TERMINALS" -eq 1 ] && echo 'install alacritty+kitty' || echo 'skip (config symlinked only)')"
info "rust:      $([ "$WITH_RUST" -eq 1 ] && echo yes || echo no)"

# ---------------------------------------------------------------------------
step "Installing apt packages"
# ---------------------------------------------------------------------------
sudo apt-get update -y
sudo apt-get install -y --no-install-recommends \
    build-essential git curl wget unzip tar gettext ca-certificates \
    stow ripgrep fd-find xclip imagemagick \
    python3 python3-venv python3-pip fontconfig
ok "core packages installed"

# fd-find ships the binary as 'fdfind' on Debian/Ubuntu; expose it as 'fd'.
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    ln -sf "$(command -v fdfind)" "$LOCAL_BIN/fd"
    ok "linked fd -> fdfind"
fi

# ---------------------------------------------------------------------------
step "Installing Node.js (NodeSource LTS)"
# ---------------------------------------------------------------------------
# Check the MAJOR version, not just presence: pyright/copilot need node >= 18, and
# an old apt/conda node left in place would break them with "Unexpected token '?'".
node_major() { node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0; }
NODE_MAJOR=0
command -v node >/dev/null 2>&1 && NODE_MAJOR="$(node_major)"
if [ "${NODE_MAJOR:-0}" -lt 18 ]; then
    info "node missing or too old (major=${NODE_MAJOR}); installing NodeSource LTS"
    # The distro nodejs/libnode-dev (e.g. Ubuntu 22.04's node 12) owns headers like
    # /usr/include/node/common.gypi and blocks the NodeSource package from unpacking
    # with a dpkg file-conflict — remove the distro packages first.
    sudo apt-get remove -y nodejs npm libnode-dev nodejs-doc >/dev/null 2>&1 || true
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
    sudo apt-get install -y nodejs
    hash -r 2>/dev/null || true
    ok "node installed: $(node --version)"
else
    ok "node already present: $(node --version)"
fi
# Global npm installs into ~/.local (no sudo).
npm config set prefix "$HOME/.local" >/dev/null 2>&1 || true

# A conda/venv node earlier on PATH can still SHADOW the one we just installed —
# and that's what launches pyright. Warn loudly if the *active* node is too old.
if command -v node >/dev/null 2>&1 && [ "$(node_major)" -lt 18 ]; then
    warn "active 'node' is v$(node_major) at $(command -v node) — too old for pyright/copilot"
    warn "it's likely a conda/venv node shadowing the system one. Upgrade it, e.g.:"
    warn "  conda install -n base -c conda-forge 'nodejs>=20'   (if it's conda's node)"
    note "pyright fails with \"Unexpected token '?'\" until 'node' resolves to >= 18."
fi

# ---------------------------------------------------------------------------
step "Installing tree-sitter CLI (needed by nvim-treesitter to compile parsers)"
# ---------------------------------------------------------------------------
# nvim-treesitter (main branch) runs `tree-sitter build` to compile parsers.
# The npm package ships a PREBUILT binary linked against a recent glibc (2.39 /
# Ubuntu 24.04); on older Ubuntu it fails at runtime with
#   "libc.so.6: version `GLIBC_2.39' not found".
# So: install via npm, then actually RUN it — if it can't execute, build the CLI
# from source with cargo (links against the local glibc, works on any Ubuntu).
ts_works() { tree-sitter --version >/dev/null 2>&1; }

if ! command -v tree-sitter >/dev/null 2>&1; then
    npm install -g tree-sitter-cli || true
    hash -r 2>/dev/null || true
fi

if ts_works; then
    ok "tree-sitter CLI works: $(tree-sitter --version)"
else
    warn "prebuilt tree-sitter CLI can't run here (glibc mismatch) — building from source with cargo"
    npm uninstall -g tree-sitter-cli >/dev/null 2>&1 || true
    # tree-sitter-cli pulls in bindgen, which needs libclang to build.
    sudo apt-get install -y libclang-dev
    ensure_rust || die "cargo needed to build tree-sitter CLI but rustup install failed"
    cargo install tree-sitter-cli
    hash -r 2>/dev/null || true
    ts_works && ok "tree-sitter CLI built: $(tree-sitter --version)" \
             || die "tree-sitter CLI still not runnable after cargo build"
fi

# ---------------------------------------------------------------------------
step "Installing Neovim ($NVIM_VERSION) from official release tarball"
# ---------------------------------------------------------------------------
NVIM_TARBALL="nvim-linux-x86_64.tar.gz"
NVIM_DIRNAME="nvim-linux-x86_64"
NVIM_URL="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${NVIM_TARBALL}"
NVIM_DEST="$HOME/.local/nvim-${NVIM_VERSION}"

install_neovim() {
    local tmp; tmp="$(mktemp -d)"
    info "downloading $NVIM_URL"
    if ! curl -fSL "$NVIM_URL" -o "$tmp/$NVIM_TARBALL"; then
        rm -rf "$tmp"
        die "failed to download Neovim '$NVIM_VERSION'. Set NVIM_VERSION to a valid tag (e.g. v0.12.0), 'stable', or 'nightly'."
    fi
    rm -rf "$NVIM_DEST"
    mkdir -p "$NVIM_DEST"
    tar -xzf "$tmp/$NVIM_TARBALL" -C "$NVIM_DEST" --strip-components=1 "$NVIM_DIRNAME" \
        || tar -xzf "$tmp/$NVIM_TARBALL" -C "$NVIM_DEST" --strip-components=1
    ln -sf "$NVIM_DEST/bin/nvim" "$LOCAL_BIN/nvim"
    rm -rf "$tmp"
}

# Reinstall when missing, when the symlink is stale, or for the moving "stable"/"nightly" channels.
if [ ! -x "$NVIM_DEST/bin/nvim" ] || [ "$NVIM_VERSION" = "stable" ] || [ "$NVIM_VERSION" = "nightly" ]; then
    install_neovim
fi
ln -sf "$NVIM_DEST/bin/nvim" "$LOCAL_BIN/nvim"
ok "neovim: $("$LOCAL_BIN/nvim" --version | head -1)"

ensure_path_in_bashrc

# ---------------------------------------------------------------------------
step "Installing $NERD_FONT Nerd Font"
# ---------------------------------------------------------------------------
if fc-list 2>/dev/null | grep -qi "${NERD_FONT}.*Nerd"; then
    ok "$NERD_FONT Nerd Font already installed"
else
    FONT_DIR="$HOME/.local/share/fonts/$NERD_FONT"
    tmp="$(mktemp -d)"
    if curl -fSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/${NERD_FONT}.zip" -o "$tmp/font.zip"; then
        mkdir -p "$FONT_DIR"
        unzip -oq "$tmp/font.zip" -d "$FONT_DIR"
        fc-cache -f "$FONT_DIR" >/dev/null 2>&1 || fc-cache -f >/dev/null 2>&1 || true
        ok "$NERD_FONT Nerd Font installed"
    else
        warn "could not download $NERD_FONT font; skipping (icons may not render)"
    fi
    rm -rf "$tmp"
fi

# ---------------------------------------------------------------------------
step "GUI terminal emulators"
# ---------------------------------------------------------------------------
if [ "$INSTALL_TERMINALS" -eq 1 ]; then
    # kitty — official installer, self-contained under ~/.local/kitty.app
    if ! command -v kitty >/dev/null 2>&1; then
        curl -fsSL https://sw.kovidgoyal.net/kitty/installer.sh | sh /dev/stdin \
            launch=n dest="$HOME/.local" || warn "kitty installer failed"
        [ -x "$HOME/.local/kitty.app/bin/kitty" ] && ln -sf "$HOME/.local/kitty.app/bin/kitty" "$LOCAL_BIN/kitty"
        command -v kitty >/dev/null 2>&1 && ok "kitty installed" || warn "kitty not installed"
    else
        ok "kitty already present"
    fi
    # alacritty — apt (universe); may be older than the 0.16+ the config targets.
    if ! command -v alacritty >/dev/null 2>&1; then
        sudo apt-get install -y alacritty && ok "alacritty installed (apt)" || \
            warn "alacritty apt install failed; install manually if you use it (config wants 0.16+)"
        note "alacritty from apt may be < 0.16; if features are missing, install a newer build (e.g. 'cargo install alacritty')."
    else
        ok "alacritty already present"
    fi
else
    info "skipping GUI terminal binaries (WSL/headless); configs still symlinked below."
fi

# ---------------------------------------------------------------------------
step "Symlinking configs into ~/.config (GNU Stow)"
# ---------------------------------------------------------------------------
# Symlink one package dir's contents into a target, backing up any pre-existing
# real (non-symlink) files first.
link_pkg() {
    local pkg="$1" target="$2"
    if [ ! -d "$REPO_DIR/$pkg" ]; then
        warn "package '$pkg' not present in repo — skipping"
        return
    fi
    mkdir -p "$target"
    local f name dest
    for f in "$REPO_DIR/$pkg"/*; do
        name="$(basename "$f")"
        dest="$target/$name"
        if [ -e "$dest" ] && [ ! -L "$dest" ]; then
            mv "$dest" "$dest.bak.$(date +%s)"
            warn "backed up existing $dest -> $dest.bak.*"
        fi
    done
    stow --dir "$REPO_DIR" --target "$target" --restow "$pkg"
    ok "linked $pkg -> $target"
}

link_pkg nvim      "$CONFIG_DIR/nvim"
link_pkg tmux      "$CONFIG_DIR/tmux"
link_pkg alacritty "$CONFIG_DIR/alacritty"
link_pkg kitty     "$CONFIG_DIR/kitty"

# ---------------------------------------------------------------------------
step "Installing TPM (Tmux Plugin Manager)"
# ---------------------------------------------------------------------------
TPM_DIR="$HOME/.tmux/plugins/tpm"
if [ ! -d "$TPM_DIR" ]; then
    git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR"
    ok "TPM cloned"
else
    ok "TPM already present"
fi

# ---------------------------------------------------------------------------
step "Optional: Rust toolchain + jupynvim remote core"
# ---------------------------------------------------------------------------
if [ "$WITH_RUST" -eq 1 ]; then
    ensure_rust || die "failed to install rustup/cargo"
    rustup target add x86_64-unknown-linux-musl
    ok "musl target added"
    note "jupynvim-core will be built after plugin bootstrap (needs the plugin cloned first)."
else
    info "skipping (pass --with-rust for the jupynvim SSH-remote feature)"
fi

# ---------------------------------------------------------------------------
step "Bootstrapping Neovim plugins / LSPs / treesitter parsers"
# ---------------------------------------------------------------------------
if [ "$SKIP_BOOTSTRAP" -eq 1 ]; then
    info "skipped (--skip-bootstrap)"
else
    info "installing plugins (lazy.nvim) ..."
    "$LOCAL_BIN/nvim" --headless "+Lazy! sync" +qa 2>&1 | tail -n 3 || warn "Lazy sync reported issues"

    # Treesitter parsers. nvim-treesitter is pinned to the `main` branch (its
    # in-config auto_install is unreliable), so we run the documented :TSInstall
    # command in a headless nvim. :TSInstall is async, so we vim.wait() — which
    # pumps the event loop — until every requested parser shows up as installed.
    if ! command -v tree-sitter >/dev/null 2>&1; then
        warn "tree-sitter CLI not on PATH — parsers can't compile; run 'npm install -g tree-sitter-cli'"
    fi
    info "installing treesitter parsers (headless :TSInstall) ..."
    TS_LUA_LIST="$(printf "'%s'," $TS_PARSERS)"   # -> 'vimdoc','javascript',...
    timeout 1800 "$LOCAL_BIN/nvim" --headless \
        -c "TSInstall $TS_PARSERS" \
        -c "lua vim.wait(1700000, function() local got = require('nvim-treesitter').get_installed(); for _, l in ipairs({${TS_LUA_LIST}}) do if not vim.tbl_contains(got, l) then return false end end; return true end, 1000)" \
        -c "qa" \
        && ok "treesitter parsers installed" \
        || warn "parser install timed out/partial — run ':TSInstall $TS_PARSERS' in nvim"

    info "installing LSP servers / tools (Mason) ..."
    timeout 900 "$LOCAL_BIN/nvim" --headless \
        -c "autocmd User MasonToolsUpdateCompleted quitall" \
        -c "MasonToolsInstall" >/dev/null 2>&1 || \
        warn "Mason install timed out/partial — it will finish on first nvim launch"
    ok "Neovim bootstrap complete"

    # jupynvim LOCAL core — needed to open/run notebooks on THIS machine (nvim
    # running here, `:JupynvimOpen`, no SSH). The Lazy build hook downloads a
    # prebuilt jupynvim-core, but — exactly like tree-sitter — that prebuilt is
    # linked against a recent glibc and WON'T run on older Ubuntu, so the backend
    # dies on spawn and `:JupynvimOpen` reports "backend not running". Test it and
    # rebuild natively from source (cargo, local glibc) if it can't execute.
    JUP_DIR="$HOME/.local/share/nvim/lazy/jupynvim"
    JUP_LOCAL_CORE="$JUP_DIR/core/target/release/jupynvim-core"
    if [ -d "$JUP_DIR/core" ]; then
        if [ -x "$JUP_LOCAL_CORE" ] && "$JUP_LOCAL_CORE" --version >/dev/null 2>&1; then
            ok "jupynvim local core works: $("$JUP_LOCAL_CORE" --version 2>/dev/null | head -1)"
        else
            warn "jupynvim local core missing/unrunnable here (glibc mismatch) — building from source"
            # common build deps for the core's Rust crates (harmless if unused)
            sudo apt-get install -y pkg-config libssl-dev
            ensure_rust || die "cargo needed to build jupynvim-core but rustup install failed"
            ( cd "$JUP_DIR/core" && cargo build --release ) \
                && ok "jupynvim local core built: $("$JUP_LOCAL_CORE" --version 2>/dev/null | head -1)" \
                || warn "jupynvim-core build failed — check the error for a missing system lib and re-run"
        fi
    fi

    # jupynvim remote core (musl, for uploading to SSH remotes via :JupynvimConnect).
    if [ "$WITH_RUST" -eq 1 ]; then
        JUP_CORE="$HOME/.local/share/nvim/lazy/jupynvim/core"
        if [ -d "$JUP_CORE" ]; then
            # shellcheck disable=SC1091
            [ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
            step "Building jupynvim-core (musl static binary)"
            ( cd "$JUP_CORE" && cargo build --release --target x86_64-unknown-linux-musl ) \
                && ok "jupynvim-core built" || warn "jupynvim-core build failed"
        else
            warn "jupynvim plugin dir not found ($JUP_CORE); skipping core build"
        fi
    fi
fi

# ---------------------------------------------------------------------------
step "Bootstrapping tmux plugins (TPM)"
# ---------------------------------------------------------------------------
if [ "$SKIP_BOOTSTRAP" -eq 1 ]; then
    info "skipped (--skip-bootstrap)"
elif [ -x "$TPM_DIR/bin/install_plugins" ]; then
    "$TPM_DIR/bin/install_plugins" >/dev/null 2>&1 && ok "tmux plugins installed" || \
        warn "TPM install had issues; open tmux and press 'prefix + I'"
else
    warn "TPM install script not found; open tmux and press 'prefix + I'"
fi

# ---------------------------------------------------------------------------
step "Done 🎉"
# ---------------------------------------------------------------------------
note "Reload your shell (open a new terminal or 'source ~/.bashrc') so 'nvim' is on PATH."
note "If already in tmux: 'tmux source ~/.config/tmux/tmux.conf' to enable kitty-graphics passthrough."
if [ "$WITH_RUST" -eq 0 ]; then
    note "For jupynvim SSH-remote plots, re-run with --with-rust (builds the core binary)."
fi
echo
for n in "${NOTES[@]}"; do echo -e "${C_YELLOW}note:${C_OFF} $n"; done
