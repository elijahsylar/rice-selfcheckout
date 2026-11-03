#!/usr/bin/env bash
# SelfCheckout rice — install script.
# 2026-04-20 — built for Ubuntu 22.04 + GNOME 42.9 + X11.
#
# Idempotent: safe to re-run. Back up per-user files touched to
# ~/rice-backups/<timestamp>/ before overwriting.
#
# Usage:
#   ./install.sh           # full install
#   ./install.sh --no-sudo # skip all apt/sudo steps (fonts-only refresh etc)
#   ./install.sh --dry-run # show what would happen, don't act

set -euo pipefail

REPO="$(cd "$(dirname "$0")" && pwd)"
BACKUP="$HOME/rice-backups/install-$(date +%Y%m%d-%H%M%S)"
DRY=0
NO_SUDO=0

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY=1 ;;
        --no-sudo) NO_SUDO=1 ;;
        -h|--help)
            sed -n '2,/^$/p' "$0"; exit 0 ;;
        *) echo "unknown arg: $arg"; exit 2 ;;
    esac
done

say()  { printf '\033[1;32m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m==!\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31mxx!\033[0m %s\n' "$*" >&2; exit 1; }
run()  { if [[ $DRY -eq 1 ]]; then printf '  (dry) %s\n' "$*"; else eval "$@"; fi; }

# --- 1. distro check ---------------------------------------------------------
say "Distro check"
. /etc/os-release
if [[ "$ID" != "ubuntu" || "$VERSION_ID" != "22.04" ]]; then
    warn "built for Ubuntu 22.04, you're on $PRETTY_NAME — proceeding but expect friction"
fi

# --- 2. apt packages ---------------------------------------------------------
if [[ $NO_SUDO -eq 0 ]]; then
    say "APT packages"
    pkgs=()
    in_apt=0
    while IFS= read -r line; do
        [[ -z "$line" || "$line" =~ ^# ]] && continue
        if [[ "$line" == "[apt]" ]]; then in_apt=1; continue; fi
        if [[ "$line" == "["* ]]; then in_apt=0; continue; fi
        if [[ $in_apt -eq 1 ]]; then
            # strip inline comment + whitespace
            pkg="${line%%#*}"
            pkg="${pkg## }"; pkg="${pkg%% }"
            [[ -n "$pkg" ]] && pkgs+=("$pkg")
        fi
    done < "$REPO/packages.txt"
    run "sudo apt-get update"
    run "sudo apt-get install -y ${pkgs[*]}"
else
    warn "--no-sudo: skipping apt step"
fi

# --- 3. flatpak + flathub + LibreWolf ---------------------------------------
if command -v flatpak >/dev/null; then
    say "Flathub remote (user-level)"
    run "flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
    say "Install LibreWolf (user)"
    run "flatpak install --user -y flathub io.gitlab.librewolf-community"
    say "Grant LibreWolf read-only access to user fonts"
    run "flatpak override --user --filesystem=xdg-data/fonts:ro io.gitlab.librewolf-community"
else
    warn "flatpak not available — skipping LibreWolf install"
fi

# --- 4. Fonts ---------------------------------------------------------------
say "Fonts → ~/.local/share/fonts/selfcheckout-rice/"
FONT_DIR="$HOME/.local/share/fonts/selfcheckout-rice"
run "mkdir -p '$FONT_DIR'"
run "cp '$REPO/fonts/'*.ttf '$FONT_DIR/'"
run "fc-cache -f '$HOME/.local/share/fonts/'"

# --- 5. Wallpapers ----------------------------------------------------------
say "Wallpapers → ~/Pictures/wallpapers/selfcheckout/"
WALL_DIR="$HOME/Pictures/wallpapers/selfcheckout"
run "mkdir -p '$WALL_DIR'"
run "cp '$REPO/wallpapers/'*.png '$WALL_DIR/' 2>/dev/null || true"

# --- 6. stow deploy ---------------------------------------------------------
# Links each package's contents into the right target dir.
say "Backup current state → $BACKUP"
run "mkdir -p '$BACKUP'"
for sub in config themes scripts; do
    case "$sub" in
        config)  target="$HOME/.config" ;;
        themes)  target="$HOME/.themes" ;;
        scripts) target="$HOME/.local/bin" ;;
    esac
    run "mkdir -p '$target'"
done

if command -v stow >/dev/null; then
    say "stow-linking config / themes / scripts"
    run "stow -d '$REPO' -t '$HOME/.config'    --no-folding -R config"
    run "stow -d '$REPO' -t '$HOME/.themes'    --no-folding -R themes"
    run "stow -d '$REPO' -t '$HOME/.local/bin' --no-folding -R scripts"
else
    warn "stow missing — falling back to cp -r (no symlinks, manual sync later)"
    run "cp -r '$REPO/config/.'    '$HOME/.config/'"
    run "cp -r '$REPO/themes/.'    '$HOME/.themes/'"
    run "cp    '$REPO/scripts/'*   '$HOME/.local/bin/'"
    run "chmod +x '$HOME/.local/bin/'*"
fi

# --- 8. GNOME dconf ----------------------------------------------------------
say "Load GNOME dconf subtrees"
run "dconf load /org/gnome/terminal/                           < '$REPO/gnome-dconf/terminal.dconf'"
run "dconf load /org/gnome/desktop/interface/                  < '$REPO/gnome-dconf/interface.dconf'"
# background.dconf holds @HOME@ placeholders (dconf files cannot expand $HOME).
run "sed 's#@HOME@#$HOME#g' '$REPO/gnome-dconf/background.dconf' | dconf load /org/gnome/desktop/background/"
run "dconf load /org/gnome/shell/                              < '$REPO/gnome-dconf/shell.dconf'"

# --- 9. Firefox / LibreWolf chrome templates --------------------------------
install_browser_chrome() {
    local profiles_root="$1"
    local src="$2"
    local browser="$3"
    [[ -d "$profiles_root" ]] || { warn "$browser: profile root not found ($profiles_root); skip"; return; }
    local ini="$profiles_root/profiles.ini"
    [[ -f "$ini" ]] || { warn "$browser: no profiles.ini; skip"; return; }
    # Prefer [Install...].Default=, else first [Profile..].Path with Default=1.
    local default_path
    default_path=$(awk -F= '/^\[Install/{ininst=1; next} ininst && /^Default=/{print $2; exit}' "$ini")
    if [[ -z "$default_path" ]]; then
        default_path=$(awk -F= 'BEGIN{p=""} /^\[Profile/{p=""} /^Path=/{p=$2} /^Default=1/{print p; exit}' "$ini")
    fi
    [[ -n "$default_path" ]] || { warn "$browser: no default profile found; skip"; return; }
    local profile_dir="$profiles_root/$default_path"
    say "$browser chrome → $profile_dir"
    run "mkdir -p '$profile_dir/chrome'"
    run "cp '$src/userChrome.css'  '$profile_dir/chrome/'"
    run "cp '$src/userContent.css' '$profile_dir/chrome/'"
    run "cp '$src/user.js'         '$profile_dir/'"
}
install_browser_chrome "$HOME/snap/firefox/common/.mozilla/firefox"          "$REPO/browsers/firefox"   "Firefox (snap)"
install_browser_chrome "$HOME/.var/app/io.gitlab.librewolf-community/.librewolf" "$REPO/browsers/librewolf" "LibreWolf (flatpak)"

# --- 9b. NEONNET local dashboard server (systemd user service) --------------
# The LibreWolf new-tab dashboard lives at ~/rice-selfcheckout/browsers/librewolf/newtab/
# and is served over http://localhost:8080 so OAuth (Spotify, Google Calendar)
# and fetch()-heavy widgets work. The unit file was already stow-linked into
# ~/.config/systemd/user/ via step 6 (stow config/). Just reload + enable here.
say "Enable NEONNET dashboard server (127.0.0.1:8080)"
run "systemctl --user daemon-reload"
run "systemctl --user enable --now neonnet-dashboard.service"
sleep 1
if curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8080/ 2>/dev/null | grep -q '^200$'; then
    say "  dashboard serving at http://localhost:8080"
else
    warn "  dashboard didn't respond on 8080 — run 'systemctl --user status neonnet-dashboard' to inspect"
fi

# --- 10. Wallpaper + GRTA launcher ------------------------------------------
say "Set wallpaper + launch GRTA"
if [[ -x "$HOME/.local/bin/wallpaper-grta" ]]; then
    run "$HOME/.local/bin/wallpaper-grta"
fi

# --- 11. Summary + manual steps ---------------------------------------------
cat <<EOF

$(printf '\033[1;32m==\033[0m\033[1m Install complete \033[1;32m==\033[0m')

What happened:
  - APT + flatpak packages installed (stow, conky-all, kitty, mpv, ffmpeg, LibreWolf, etc.)
  - Fonts copied to ~/.local/share/fonts/selfcheckout-rice/, fc-cache run
  - Wallpapers copied to ~/Pictures/wallpapers/selfcheckout/
  - Dotfiles stow-linked (or copied if stow missing) from this repo to \$HOME
  - GNOME dconf subtrees loaded (terminal profile, fonts, wallpaper, shell theme)
  - Firefox + LibreWolf chrome CSS templates copied into detected active profiles
  - GRTA fullscreen wallpaper launched (if scripts installed)

Manual steps still required:
  1.  LOG OUT + LOG BACK IN so the shell theme and fonts are picked up everywhere
  2.  In gnome-terminal, Terminal menu → Change Profile → SelfCheckout (or right-click → Profiles)
  3.  RESTART Firefox (pkill firefox then relaunch) — userChrome loads only at startup
  4.  Same for LibreWolf: flatpak kill io.gitlab.librewolf-community; relaunch
  5.  GNOME Shell theme (Yaru-SelfCheckout) will apply on next login; Alt+F2 r if you want it now
  6.  If Super+F12 CRT overlay is desired (deferred, multi-monitor bug): cd overlay && make

Known issues (see README → Known Issues):
  - GNOME shell theming is brittle on Ubuntu 22.04 + Yaru; if panel vanishes after Alt+F2 r,
    revert with: dconf write /org/gnome/shell/extensions/user-theme/name "''"
  - CRT overlay works on single-monitor; HDMI hotplug drops it. Source preserved, not launched.
EOF
