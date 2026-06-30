#!/bin/sh
set -e

WORKSPACE="$(cd "$(dirname "$0")/.." && pwd)"
. "$WORKSPACE/scripts/project-targets.sh"

case "${1:-}" in
    --targets)
        print_targets
        exit 0
        ;;
esac

# Regenerate the per-user fish completion from the freshly installed binary.
# Every completion is derived from the binary itself (`<bin> completions fish`),
# so it must be re-emitted on each install or it goes stale. chezmoi's
# run_onchange_install-packages.sh.tmpl owns the same generation for fresh
# machines (plus stale pre-rename file sweeps); this hook keeps the local
# completion in lockstep with the binary without waiting on a '# hash:' bump.
install_fish_completion() {
    bin_path="$1"
    bin_name="$(basename "$bin_path")"
    if ! command -v fish >/dev/null 2>&1; then
        return 0
    fi
    completions_dir="$HOME/.config/fish/completions"
    mkdir -p "$completions_dir"
    "$bin_path" completions fish > "$completions_dir/$bin_name.fish"
    echo "Fish completions regenerated: $completions_dir/$bin_name.fish"
}

TARGET="${1:-upstream}"
if ! DIR="$(target_dir "$TARGET")"; then
    usage_targets "$0"
    exit 1
fi

if [ ! -d "$DIR" ]; then
    echo "Error: $DIR does not exist." >&2
    exit 1
fi

# Install a tool's per-user systemd unit when its repo ships one
# (systemd/<bin>.service). Mirrors the compositor regime's unit handling,
# but per-user: ~/.config/systemd/user, no sudo. try-restart picks up new
# binaries on upgrade without touching a unit that isn't enabled/running.
install_user_unit() {
    unit_src="$1"
    unit_name="$(basename "$unit_src")"
    units_dir="$HOME/.config/systemd/user"
    install -Dm644 "$unit_src" "$units_dir/$unit_name"
    systemctl --user daemon-reload
    systemctl --user try-restart "$unit_name" 2>/dev/null || true
    echo "Systemd user unit installed: $units_dir/$unit_name"
    if ! systemctl --user is-enabled --quiet "$unit_name" 2>/dev/null; then
        echo "Enable it with: systemctl --user enable --now $unit_name"
    fi
}

# ── waf regime: Python/GTK fork (hamster), system-wide via sudo ./waf install ─
# build.sh runs `./waf configure build` as the user; we only do the root install
# step here, matching upstream's `( umask 0022 && sudo ./waf install )` flow.
if [ "$(target_regime "$TARGET")" = waf ]; then
    echo "Installing $TARGET system-wide (sudo ./waf install)..."
    cd "$DIR"
    if [ ! -d build ]; then
        echo "Error: no waf build/ in $DIR. Run ./scripts/build.sh $TARGET first." >&2
        exit 1
    fi
    ( umask 0022 && sudo ./waf install )
    echo "Done. $(target_bin "$TARGET") installed system-wide."
    echo "Uninstall with: (cd $DIR && sudo ./waf uninstall)"
    exit 0
fi

# ── Cargo tool regime: per-user cargo install into ~/.cargo/bin ──────────────
if [ "$(target_regime "$TARGET")" = cargo ]; then
    BIN_NAME="$(target_bin "$TARGET")"
    echo "Installing $TARGET to ~/.cargo/bin (cargo install --offline)..."
    cd "$DIR"
    cargo install --path . --offline
    echo "Done. $BIN_NAME installed to ~/.cargo/bin/$BIN_NAME"
    if [ -f "$DIR/systemd/$BIN_NAME.service" ]; then
        install_user_unit "$DIR/systemd/$BIN_NAME.service"
    fi
    case "$TARGET" in
        jiji-activities|jiji-do)
            install_fish_completion "$HOME/.cargo/bin/$BIN_NAME"
            echo ""
            echo "Note: if the CLI surface changed (verbs/flags), also bump '# hash:' in"
            echo "chezmoi's run_onchange_install-packages.sh.tmpl so fresh machines"
            echo "regenerate their completions on the next 'chezmoi apply'."
            ;;
    esac
    exit 0
fi

# ── Compositor regime: system-wide install (binary + session files) ──────────

# Detect binary name (jiji after compositor source rename, niri otherwise).
if [ -f "$DIR/target/release/jiji" ]; then
    BIN_NAME=jiji
elif [ -f "$DIR/target/release/niri" ]; then
    BIN_NAME=niri
else
    echo "Error: no built binary in $DIR/target/release/. Run ./scripts/build.sh $TARGET first." >&2
    exit 1
fi

BINARY="$DIR/target/release/$BIN_NAME"

echo "Installing $BIN_NAME from $TARGET..."

# Binary
sudo install -Dm755 "$BINARY" "/usr/local/bin/$BIN_NAME"

# Session launcher. Filename follows the binary name; upstream ships
# 'niri-session', a post-rename jiji ships 'jiji-session'.
if [ -f "$DIR/resources/$BIN_NAME-session" ]; then
    sudo install -Dm755 "$DIR/resources/$BIN_NAME-session" "/usr/local/bin/$BIN_NAME-session"
fi

# Wayland session / portals config.
if [ -f "$DIR/resources/$BIN_NAME.desktop" ]; then
    sudo install -Dm644 "$DIR/resources/$BIN_NAME.desktop" "/usr/local/share/wayland-sessions/$BIN_NAME.desktop"
fi
if [ -f "$DIR/resources/$BIN_NAME-portals.conf" ]; then
    sudo install -Dm644 "$DIR/resources/$BIN_NAME-portals.conf" "/usr/local/share/xdg-desktop-portal/$BIN_NAME-portals.conf"
fi

# Systemd user units.
if [ -f "$DIR/resources/$BIN_NAME.service" ]; then
    sudo install -Dm644 "$DIR/resources/$BIN_NAME.service" "/etc/systemd/user/$BIN_NAME.service"
fi
if [ -f "$DIR/resources/$BIN_NAME-shutdown.target" ]; then
    sudo install -Dm644 "$DIR/resources/$BIN_NAME-shutdown.target" "/etc/systemd/user/$BIN_NAME-shutdown.target"
fi

install_fish_completion "/usr/local/bin/$BIN_NAME"

echo "Done. $BIN_NAME installed to /usr/local/bin/$BIN_NAME"
