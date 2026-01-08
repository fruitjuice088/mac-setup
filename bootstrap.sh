#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# mac-setup bootstrap
# - Install Homebrew + brew bundle (Brewfile)
# - Import app defaults (AltTab / AutoRaise / MiddleClick)
# - Install MouseJumpUtility from GitHub release zip
# - Apply Karabiner + VSCode settings
# - Install VSCode extensions
# ============================================================

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BREWFILE="${ROOT_DIR}/Brewfile"

# Defaults domains
DOMAIN_ALTTAB="com.lwouis.alt-tab-macos"
DOMAIN_AUTORAISE="com.sbmpost.AutoRaise"
DOMAIN_MIDDLECLICK="art.ginzburg.MiddleClick"

# Config paths in repo
DEFAULTS_DIR="${ROOT_DIR}/config/defaults"
KARABINER_SRC="${ROOT_DIR}/config/karabiner/karabiner.json"
VSCODE_SETTINGS_SRC="${ROOT_DIR}/config/vscode/settings.json"
VSCODE_EXT_SRC="${ROOT_DIR}/config/vscode/extensions.txt"

# MouseJumpUtility
MJU_URL="https://github.com/fruitjuice088/MouseJumpUtility/releases/download/v1.0.0/MouseJumpUtility.zip"
MJU_APP_NAME="MouseJumpUtility.app"

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Command not found: $1"
}

is_macos() {
  [[ "$(uname -s)" == "Darwin" ]]
}

install_xcode_clt_if_needed() {
  log "==> [1] Xcode Command Line Tools"
  if xcode-select -p >/dev/null 2>&1; then
    log "    Xcode CLT already installed."
    return 0
  fi

  log "    Installing Xcode CLT (GUI prompt will appear)."
  xcode-select --install || true
  log "    Complete the GUI installer, then re-run bootstrap.sh."
  exit 1
}

install_homebrew_if_needed() {
  log "==> [2] Homebrew"
  if command -v brew >/dev/null 2>&1; then
    log "    Homebrew already installed."
  else
    log "    Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi

  # Ensure brew is on PATH (especially on Apple Silicon)
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  need_cmd brew
  log "    brew: $(brew --version | head -n 1)"
}

brew_bundle() {
  log "==> [3] brew bundle"
  [[ -f "$BREWFILE" ]] || die "Brewfile not found: $BREWFILE"
  brew update
  brew bundle --file "$BREWFILE"
}

import_defaults_if_present() {
  log "==> [4] Import app preferences (defaults)"
  [[ -d "$DEFAULTS_DIR" ]] || die "Defaults directory not found: $DEFAULTS_DIR"

  local changed=0

  if [[ -f "${DEFAULTS_DIR}/alt-tab.plist" ]]; then
    log "    Import AltTab: ${DOMAIN_ALTTAB}"
    defaults import "${DOMAIN_ALTTAB}" "${DEFAULTS_DIR}/alt-tab.plist"
    changed=1
  else
    log "    Skip AltTab (plist not found): ${DEFAULTS_DIR}/alt-tab.plist"
  fi

  if [[ -f "${DEFAULTS_DIR}/autoraise.plist" ]]; then
    log "    Import AutoRaise: ${DOMAIN_AUTORAISE}"
    defaults import "${DOMAIN_AUTORAISE}" "${DEFAULTS_DIR}/autoraise.plist"
    changed=1
  else
    log "    Skip AutoRaise (plist not found): ${DEFAULTS_DIR}/autoraise.plist"
  fi

  if [[ -f "${DEFAULTS_DIR}/middleclick.plist" ]]; then
    log "    Import MiddleClick: ${DOMAIN_MIDDLECLICK}"
    defaults import "${DOMAIN_MIDDLECLICK}" "${DEFAULTS_DIR}/middleclick.plist"
    changed=1
  else
    log "    Skip MiddleClick (plist not found): ${DEFAULTS_DIR}/middleclick.plist"
  fi

  if [[ "$changed" -eq 1 ]]; then
    log "    Restarting preference daemon (cfprefsd) for faster propagation."
    killall cfprefsd >/dev/null 2>&1 || true
  fi
}

install_mousejumputility() {
  log "==> [5] Install MouseJumpUtility (.zip -> .app)"
  local tmpdir
  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' RETURN

  need_cmd curl
  need_cmd unzip

  log "    Downloading: ${MJU_URL}"
  curl -fsSL "$MJU_URL" -o "${tmpdir}/MouseJumpUtility.zip"

  log "    Unzipping..."
  unzip -q "${tmpdir}/MouseJumpUtility.zip" -d "${tmpdir}/unzipped"

  local app_path
  app_path="$(find "${tmpdir}/unzipped" -maxdepth 3 -name "${MJU_APP_NAME}" -print -quit || true)"
  [[ -n "$app_path" ]] || die "Could not find ${MJU_APP_NAME} in the zip."

  if [[ -d "/Applications/${MJU_APP_NAME}" ]]; then
    log "    Already installed: /Applications/${MJU_APP_NAME} (skip)"
    return 0
  fi

  log "    Copying to /Applications (requires sudo)..."
  sudo cp -R "$app_path" /Applications/

  log "    Installed: /Applications/${MJU_APP_NAME}"
  log "    NOTE: On first launch, Gatekeeper may block it (manual allow may be required)."
}

apply_karabiner_config() {
  log "==> [6] Apply Karabiner config"
  if [[ ! -f "$KARABINER_SRC" ]]; then
    log "    Skip (not found): $KARABINER_SRC"
    return 0
  fi

  local dst_dir="${HOME}/.config/karabiner"
  mkdir -p "$dst_dir"
  cp "$KARABINER_SRC" "${dst_dir}/karabiner.json"
  log "    Applied: ${dst_dir}/karabiner.json"
}

apply_vscode_settings() {
  log "==> [7] Apply VSCode settings.json"
  if [[ ! -f "$VSCODE_SETTINGS_SRC" ]]; then
    log "    Skip (not found): $VSCODE_SETTINGS_SRC"
    return 0
  fi

  local dst_dir="${HOME}/Library/Application Support/Code/User"
  mkdir -p "$dst_dir"
  cp "$VSCODE_SETTINGS_SRC" "${dst_dir}/settings.json"
  log "    Applied: ${dst_dir}/settings.json"
}

install_vscode_extensions() {
  log "==> [8] Install VSCode extensions"
  if [[ ! -f "$VSCODE_EXT_SRC" ]]; then
    log "    Skip (not found): $VSCODE_EXT_SRC"
    return 0
  fi

  # code command is installed by VSCode: "Shell Command: Install 'code' command in PATH"
  if ! command -v code >/dev/null 2>&1; then
    log "    'code' command not found."
    log "    Open VSCode once, then run: Command Palette -> 'Shell Command: Install 'code' command in PATH'"
    log "    After that, re-run bootstrap.sh (or just run the extension install section manually)."
    return 0
  fi

  while IFS= read -r ext || [[ -n "$ext" ]]; do
    [[ -z "$ext" ]] && continue
    log "    Installing: $ext"
    code --install-extension "$ext" >/dev/null || true
  done < "$VSCODE_EXT_SRC"

  log "    Done."
}

main() {
  is_macos || die "This script is intended for macOS only."

  install_xcode_clt_if_needed
  install_homebrew_if_needed
  brew_bundle

  import_defaults_if_present
  install_mousejumputility
  apply_karabiner_config
  apply_vscode_settings
  install_vscode_extensions

  log "All automated steps completed."
}

main "$@"
