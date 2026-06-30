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

# A fork whose jiji-wm repo may not exist yet: clone from origin when it does,
# otherwise bootstrap the working tree from upstream and wire the remotes
# (origin -> the eventual jiji-wm repo, <upstream_remote> -> the real upstream
# for rebases). Idempotent and correct in both phases — once the jiji-wm repo is
# pushed, the origin clone path takes over.
clone_fork() {
    origin_url="$1"
    upstream_url="$2"
    upstream_remote="$3"
    dest="$4"

    if [ -d "$dest/.git" ]; then
        echo "Already cloned: $dest"
    elif git clone "$origin_url" "$dest" 2>/dev/null; then
        echo "Cloned fork from origin: $origin_url -> $dest"
    else
        echo "Origin $origin_url unavailable — bootstrapping fork from upstream"
        git clone "$upstream_url" "$dest"
        git -C "$dest" remote rename origin "$upstream_remote"
        git -C "$dest" remote add origin "$origin_url"
        git -C "$dest" branch -m main 2>/dev/null || true
    fi
    # Ensure the upstream remote is present either way (needed for rebases).
    git -C "$dest" remote get-url "$upstream_remote" >/dev/null 2>&1 \
        || git -C "$dest" remote add "$upstream_remote" "$upstream_url"
}

# Upstream mirrors (read-only, kept for rebase reference).
clone_repo "git@github.com:niri-wm/niri.git"             "$WORKSPACE_DIR/repos/upstream/niri"
clone_repo "git@github.com:Alexays/Waybar.git"           "$WORKSPACE_DIR/repos/upstream/waybar"
clone_repo "git@github.com:projecthamster/hamster.git"   "$WORKSPACE_DIR/repos/upstream/hamster"

# jiji compositor + tools (jiji-wm org).
clone_repo "git@github.com:jiji-wm/jiji.git"                    "$WORKSPACE_DIR/repos/jiji"
clone_repo "git@github.com:jiji-wm/jiji-activities.git"         "$WORKSPACE_DIR/repos/jiji-activities"
clone_repo "git@github.com:jiji-wm/jiji-do.git"                 "$WORKSPACE_DIR/repos/jiji-do"
clone_repo "git@github.com:jiji-wm/jiji-firefox-workspaces.git" "$WORKSPACE_DIR/repos/jiji-firefox-workspaces"
clone_repo "git@github.com:jiji-wm/jiji-hamster-bridge.git"     "$WORKSPACE_DIR/repos/jiji-hamster-bridge"
clone_repo "git@github.com:jiji-wm/jiji-waybar.git"             "$WORKSPACE_DIR/repos/jiji-waybar"

# jiji-hamster: fork of projecthamster/hamster (Python/GTK, waf build). The
# jiji-wm repo is pushed manually; until then this bootstraps from upstream.
clone_fork "git@github.com:jiji-wm/jiji-hamster.git" \
           "git@github.com:projecthamster/hamster.git" \
           "hamster-upstream" \
           "$WORKSPACE_DIR/repos/jiji-hamster"

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
