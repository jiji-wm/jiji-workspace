# Installing niri on Debian

Guide for setting up niri from source on Debian (tested on Debian 14 / trixie).

## 1. Build dependencies

```sh
sudo apt install gcc clang libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev \
  libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev libseat-dev \
  libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev
```

You also need Rust (stable, >= 1.85). Install via [rustup](https://rustup.rs/) if not already available.

## 2. Build and install niri

```sh
./scripts/build.sh       # cargo build --release (upstream; pass a target for others)
./scripts/install.sh     # installs to /usr/local/ and /etc/systemd/user/
```

Both scripts take an optional target (`--targets` lists them): `upstream` (default) and `jiji` install the compositor system-wide as above; the cargo tool targets (`jiji-activities`, `jiji-do`, `jiji-firefox-workspaces`, `jiji-hamster-bridge`) are installed per-user into `~/.cargo/bin` via `cargo install` (plus the tool's systemd user unit, when its repo ships one under `systemd/`); `jiji-hamster` (Python/GTK, **waf** build) installs system-wide via `sudo ./waf install` — see its section below.

This installs:

| File | Destination |
|------|-------------|
| `niri` binary | `/usr/local/bin/niri` |
| `niri-session` script | `/usr/local/bin/niri-session` |
| `niri.desktop` | `/usr/local/share/wayland-sessions/niri.desktop` |
| `niri-portals.conf` | `/usr/local/share/xdg-desktop-portal/niri-portals.conf` |
| `niri.service` | `/etc/systemd/user/niri.service` |
| `niri-shutdown.target` | `/etc/systemd/user/niri-shutdown.target` |

### systemd service path note

The installed `niri.service` uses `ExecStart=niri --session` (bare name). Systemd resolves this via PATH, which normally includes `/usr/local/bin`. If niri fails to start via `niri-session`, edit the service to use an absolute path:

```sh
sudo sed -i 's|ExecStart=niri|ExecStart=/usr/local/bin/niri|' /etc/systemd/user/niri.service
systemctl --user daemon-reload
```

### lightdm session discovery

Lightdm's default `sessions-directory` only searches `/usr/share/wayland-sessions/`, not `/usr/local/share/wayland-sessions/`. The install script puts `niri.desktop` in the `/usr/local/` path, so **lightdm won't show niri as a session option** without one of these fixes:

**Option A** — symlink into the standard path:
```sh
sudo ln -s /usr/local/share/wayland-sessions/niri.desktop /usr/share/wayland-sessions/niri.desktop
```

**Option B** — add the path to lightdm config. Uncomment and extend `sessions-directory` in `/etc/lightdm/lightdm.conf`:
```ini
[LightDM]
sessions-directory=/usr/share/lightdm/sessions:/usr/share/xsessions:/usr/share/wayland-sessions:/usr/local/share/wayland-sessions
```

GDM and SDDM check both paths by default, so this is lightdm-specific.

You can always bypass the display manager entirely by running `niri-session` from a TTY.

## 3. Essential system packages

These are required for a functional desktop session:

```sh
sudo apt install \
  xdg-desktop-portal-gnome \
  xdg-desktop-portal-gtk \
  gnome-keyring \
  nautilus
```

- **xdg-desktop-portal-gnome** — required for screencasting; referenced in `niri-portals.conf`. Pulls in `xdg-desktop-portal-gtk` as a dependency.
- **xdg-desktop-portal-gtk** — fallback portal for file pickers, notifications, etc.
- **gnome-keyring** — Secret portal provider (required by some apps for credential storage)
- **nautilus** — file chooser backend for xdg-desktop-portal-gnome >= 47.0 (hard dependency)

If you don't want nautilus as your file manager but need it for the portal, it only needs to be installed — you don't have to use it. Alternatively, edit `/usr/local/share/xdg-desktop-portal/niri-portals.conf` and set `org.freedesktop.impl.portal.FileChooser=gtk;` to use the GTK file chooser instead.

## 4. Desktop tools

Core tools for daily use (all in Debian repos):

```sh
sudo apt install \
  alacritty \
  fuzzel \
  sway-notification-center \
  waybar \
  swaylock \
  swaybg \
  fonts-font-awesome \
  wl-clipboard \
  grim \
  slurp \
  copyq \
  qt5ct \
  qt6ct
```

| Package | Tool | Purpose | Default keybind |
|---------|------|---------|-----------------|
| alacritty | alacritty | Terminal emulator (default, replaced by wezterm) | — |
| fuzzel | fuzzel | Application launcher (default, replaced by rofi) | — |
| sway-notification-center | swaync | Notification center (history, DND, grouped) | (background service) |
| waybar | waybar | Status bar | (spawned at startup) |
| swaylock | swaylock | Screen locker | — |
| swaybg | swaybg | Wallpaper setter | (spawned at startup) |
| fonts-font-awesome | — | Icon font used by waybar's default config | — |
| wl-clipboard | wl-copy, wl-paste | Clipboard CLI for Wayland | — |
| grim | grim | Wayland screenshot capture | Print (via satty pipeline) |
| slurp | slurp | Interactive region selector for Wayland | (used by scripts) |
| copyq | copyq | Clipboard history manager (text + images, GUI picker) | — |
| qt5ct / qt6ct | qt5ct, qt6ct | Qt platform theme — color scheme switched by `theme-switch` (dark/light) | — |

If you already have preferred alternatives (e.g. kitty/wezterm for terminal, rofi for launcher), you can skip the corresponding package and rebind in the niri config instead. The default config expects alacritty and fuzzel.

#### jiji-waybar (Waybar fork with jiji modules)

The workspace ships a Waybar fork at `repos/jiji-waybar` that adds jiji-specific
activities modules. The stock Debian `waybar` package works fine for everything
else; build the fork only if you want those modules.

```sh
# Build deps — easiest on Debian with deb-src enabled:
sudo apt build-dep waybar
# (otherwise install manually: meson ninja-build libgtkmm-3.0-dev libjsoncpp-dev
#  libspdlog-dev libfmt-dev libwayland-dev libgtk-layer-shell-dev scdoc plus the
#  optional feature deps you need)

# Build and install the fork (installs to /usr/local, shadowing the apt package)
cd repos/jiji-waybar
meson setup build -Djiji=true
ninja -C build
sudo ninja -C build install
```

The jiji activities module shells out to `jiji-activities`, so that binary must
be on `PATH` (see "jiji-activities" below) and a jiji session must be running.

### Screenshot annotation (Satty)

[Satty](https://github.com/gabm/Satty) is a Wayland-native screenshot annotation editor (crop, arrows, numbered markers, text, blur, rectangles). Not in Debian repos — install via cargo:

```sh
# Build dependencies (libgtk-4-dev and libadwaita-1-dev may already be installed)
sudo apt install libgtk-4-dev libadwaita-1-dev

# Install satty
cargo install satty
```

The niri config binds `Print` to: `grim - | ~/.cargo/bin/satty --filename -` (capture full screen, open Satty for annotation/crop, then save to disk or clipboard). The full path to satty is required because niri's `spawn-sh` uses `/bin/sh` which doesn't have `~/.cargo/bin` in PATH.

### Polkit authentication agent

You need a polkit agent for apps that request root permissions. If you already have a desktop environment installed, you likely have one (lxpolkit, mate-polkit, polkit-kde-agent). Otherwise:

```sh
sudo apt install lxpolkit   # lightweight option
```

Start it via `spawn-at-startup` in the niri config or a systemd user service.

## 5. Xwayland (X11 app support)

Niri is a Wayland-only compositor — it doesn't have built-in X11 support. X11 applications (Steam, Wine/Proton games, some Electron apps) need an X11 server to run. [xwayland-satellite](https://github.com/Supreeeme/xwayland-satellite) bridges this gap: it runs Xwayland and re-exports each X11 window as an independent Wayland window that niri can manage normally (tile, float, move between workspaces, etc.).

Since niri >= 25.08, the integration is automatic — niri creates X11 sockets, exports `$DISPLAY`, and spawns xwayland-satellite on demand when an X11 client connects. You just need the binary in `$PATH`.

`xwayland-satellite` is **not in Debian repos** as of trixie. Install from git via cargo:

```sh
# Build dependency
sudo apt install libxcb-cursor-dev

# Install (builds from source, binary goes to ~/.cargo/bin/)
cargo install --git https://github.com/Supreeeme/xwayland-satellite
```

The `xwayland` package (the underlying X server) must also be installed — it likely already is:
```sh
sudo apt install xwayland
```

Verify after starting niri:
```sh
journalctl --user-unit=niri -b | grep "X11 socket"
# Should show: listening on X11 socket: :0
```

Without xwayland-satellite, niri works fine for native Wayland apps. Many Electron apps (VSCode, Discord) can run natively on Wayland with `--ozone-platform=wayland`.

To update xwayland-satellite later, re-run the same `cargo install --git` command. To clone the repo locally instead (e.g. into the `de/` workspace):
```sh
git clone https://github.com/Supreeeme/xwayland-satellite
cd xwayland-satellite && cargo build --release
cp target/release/xwayland-satellite ~/.cargo/bin/
```

## 6. Create your config

```sh
mkdir -p ~/.config/niri
cp niri/resources/default-config.kdl ~/.config/niri/config.kdl
```

Edit `~/.config/niri/config.kdl` to customize:
- Replace `alacritty` / `fuzzel` with your preferred terminal / launcher
- Remove `spawn-at-startup "waybar"` if using a different bar or shell
- Add `spawn-at-startup` entries for notification daemon, polkit agent, wallpaper, etc.

## 7. Start niri

**From a display manager:** log out, select "Niri" from the session list, log in. See the lightdm note above if niri doesn't appear.

**From a TTY:** run `niri-session`. This starts niri as a systemd service with proper session management, D-Bus activation, and portal support.

**For testing (nested in existing session):** run `niri` directly. It opens as a window. Mod key becomes Alt instead of Super. Mainly useful for development.

## 8. Verify the installation

After starting niri, check:

```sh
niri --version                    # compositor version
niri msg version                  # IPC is working
echo $WAYLAND_DISPLAY             # should be wayland-1 or similar
echo $DISPLAY                     # should be :0 if xwayland-satellite is running
systemctl --user status niri      # systemd service is active
```

## Package summary

Everything installed from Debian repos for a full niri desktop:

```
# Build deps
gcc clang libudev-dev libgbm-dev libxkbcommon-dev libegl1-mesa-dev
libwayland-dev libinput-dev libdbus-1-dev libsystemd-dev libseat-dev
libpipewire-0.3-dev libpango1.0-dev libdisplay-info-dev

# Portals & session
xdg-desktop-portal-gnome xdg-desktop-portal-gtk gnome-keyring nautilus

# Desktop tools
alacritty fuzzel sway-notification-center waybar swaylock swaybg
fonts-font-awesome wl-clipboard grim slurp jq inotify-tools

# jiji-hamster build deps (waf build; itstool/yelp optional) + hamster D-Bus service
gettext intltool python3-gi python3-cairo python3-gi-cairo python3-dbus
libglib2.0-dev libglib2.0-bin gir1.2-gtk-3.0 gtk-update-icon-cache itstool yelp
hamster-time-tracker

# Not in Debian repos (install via cargo)
# libxcb-cursor-dev — build dependency for xwayland-satellite
# libgtk-4-dev libadwaita-1-dev — build dependencies for satty
# xwayland-satellite — cargo install --git https://github.com/Supreeeme/xwayland-satellite
# satty — cargo install satty
```

## Optional: recommended ecosystem tools

These are available in the parent `de/` workspace (see `../CLAUDE.md` for the full inventory). Build with `cargo build --release` in each repo.

| Tool | Repo dir | Purpose |
|------|----------|---------|
| niri-ror | `<sibling-checkout>/niri-ror` | Raise-or-run: focus an app or launch it |
| ndrop | `<sibling-checkout>/ndrop` | Dropdown terminal emulation |
| stasis | `../system/stasis` | Smart idle manager (media-aware, replaces swayidle) |
| niri-taskbar | `<sibling-checkout>/niri-taskbar` | Taskbar module for Waybar |

### jiji-activities (KDE-style activities — fork-only feature)

The activities feature lives on the jiji fork (`./scripts/build.sh jiji` and `./scripts/install.sh jiji` in step 2 above). Once installed, the `jiji-activities` CLI provides the user-facing surface.

```sh
# Runtime dependencies for the pickers
sudo apt install fuzzel rofi

# Install the CLI binary (user-local, no sudo; also regenerates fish completions)
./scripts/build.sh jiji-activities
./scripts/install.sh jiji-activities
```

Keybindings are pre-configured in the chezmoi niri config (see `keybindings.md` → "Activities"). The activities IPC requires the jiji fork; on upstream niri the binary itself works but `jiji-activities switch` etc. will fail with `socket unavailable` / `malformed response`.

### jiji-firefox-workspaces (per-workspace Firefox window restore)

Restores Firefox windows to the workspace each was last on, across compositor
and Firefox restarts. Three pieces: a native-messaging host (Rust), a Firefox
WebExtension, and the host's discovery manifest.

```sh
# 1. Host binary (user-local, no sudo)
cd repos/jiji-firefox-workspaces
cargo install --path . --locked

# 2. Native-messaging manifest — deployed by chezmoi
#    (run_onchange_install-packages.sh writes
#    ~/.mozilla/native-messaging-hosts/org.gajdusek.jiji_firefox_workspaces.json
#    pointing at ~/.cargo/bin/jiji-firefox-workspaces-host)
chezmoi apply

# 3. Extension — depends on the Firefox channel:
#    ESR/Dev/Nightly: xpinstall.signatures.required=false, then
#      npx web-ext build --source-dir repos/jiji-firefox-workspaces/extension
#      and install the .zip via about:addons -> gear -> Install Add-on From File
#    Release/beta (signing enforced): sign via AMO unlisted channel —
#      repos/jiji-firefox-workspaces/extension/sign.sh (needs AMO API keys;
#      see that extension/README.md for the full walkthrough)
```

Works against both compositor regimes: on a jiji build with the `app_tag`
IPC field the host reads the structured tag; on upstream niri / older jiji
it falls back to parsing the invisible title marker.

### jiji-hamster (forked GNOME Hamster time tracker)

Fork of [hamster](https://github.com/projecthamster/hamster) (Python/GTK, waf
build) — the time-tracker app the bridge below drives over `org.gnome.Hamster`
D-Bus. Install this instead of the Debian `hamster-time-tracker` package when you
want the jiji-specific patches. The working clone keeps upstream as the
`hamster-upstream` git remote for rebases.

```sh
# 1. Build deps (Python/GTK runtime + GNOME doc tooling; itstool/yelp optional —
#    without them the docs build is auto-disabled)
sudo apt install gettext intltool python3-gi python3-cairo python3-gi-cairo \
    python3-dbus libglib2.0-dev libglib2.0-bin gir1.2-gtk-3.0 \
    gtk-update-icon-cache itstool yelp

# 2. Build (./waf configure build) then install system-wide (sudo ./waf install)
./scripts/build.sh jiji-hamster
./scripts/install.sh jiji-hamster
```

Uninstall with `(cd repos/jiji-hamster && sudo ./waf uninstall)`.

### jiji-hamster-bridge (activity-driven hamster time tracking)

Pauses/resumes/switches [hamster](https://github.com/projecthamster/hamster)
time tracking based on the focused jiji activity (with named-workspace
overrides). Facts are matched by `entity:` tag, today-only, with tagged
placeholder facts created on first contact of the day.

```sh
# 1. Hamster itself (Debian package tracks upstream 3.0.3)
sudo apt install hamster-time-tracker

# 2. Bridge binary + systemd user unit (user-local, no sudo)
./scripts/install.sh jiji-hamster-bridge

# 3. Config — deployed by chezmoi
#    (~/.config/jiji-hamster-bridge/config.toml: tracked activities,
#    entity tags, debounce knobs; hot-reloaded on change, SIGHUP forces)
chezmoi apply

# 4. Enable (once; later installs auto-restart a running daemon)
systemctl --user enable --now jiji-hamster-bridge.service
```

Requires a jiji session (`jiji msg` event stream); on upstream niri the
daemon idles (no activity events). Logs: `journalctl --user -u
jiji-hamster-bridge`.

## Upgrading

```sh
cd niri && git pull
cd ..
./scripts/build.sh
./scripts/install.sh
systemctl --user restart niri     # or log out and back in
```

## Uninstalling

```sh
./scripts/uninstall.sh
```
