#!/bin/sh
set -e

WORKSPACE_DIR="$(cd "$(dirname "$0")/.." && pwd)"

clone_repo() {
    url="$1"
    dest="$2"

    if [ -d "$dest/.git" ]; then
        echo "Already cloned: $dest"
        return
    fi

    echo "Cloning $url -> $dest"
    git clone "$url" "$dest"
}

# Upstream mirrors (read-only, kept for rebase reference).
clone_repo "git@github.com:niri-wm/niri.git"   "$WORKSPACE_DIR/repos/upstream/niri"
clone_repo "git@github.com:Alexays/Waybar.git" "$WORKSPACE_DIR/repos/upstream/waybar"

# jiji compositor + tools (jiji-wm org).
clone_repo "git@github.com:jiji-wm/jiji.git"                    "$WORKSPACE_DIR/repos/jiji"
clone_repo "git@github.com:jiji-wm/jiji-activities.git"         "$WORKSPACE_DIR/repos/jiji-activities"
clone_repo "git@github.com:jiji-wm/jiji-do.git"                 "$WORKSPACE_DIR/repos/jiji-do"
clone_repo "git@github.com:jiji-wm/jiji-firefox-workspaces.git" "$WORKSPACE_DIR/repos/jiji-firefox-workspaces"
clone_repo "git@github.com:jiji-wm/jiji-hamster-bridge.git"     "$WORKSPACE_DIR/repos/jiji-hamster-bridge"
clone_repo "git@github.com:jiji-wm/jiji-waybar.git"             "$WORKSPACE_DIR/repos/jiji-waybar"

# Curated niri awesome-list (community contribution to upstream niri).
clone_repo "git@github.com:niri-wm/awesome-niri.git" "$WORKSPACE_DIR/repos/reference/awesome-niri"

# Private overlay (DDs/specs/plans/status). Optional: requires access; public
# contributors skip it and work with an empty private/ (degrades gracefully).
if [ ! -d "$WORKSPACE_DIR/private/.git" ]; then
    echo "Cloning private overlay -> private/ (skipped if no access)"
    git clone "git@github.com:jiji-wm/jiji-specs-private.git" "$WORKSPACE_DIR/private" \
        || echo "Private overlay not cloned (no access) — continuing without it."
else
    echo "Already cloned: $WORKSPACE_DIR/private"
fi

echo ""
echo "All repos cloned."
