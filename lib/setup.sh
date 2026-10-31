# doomscroller init: links the command and the Claude Code hook, adds the
# hook to Claude's settings, asks for preferences and checks permissions.
# Every step looks before it acts and asks before changing anything outside
# ~/.doomscroller, so running it again is safe.

CLAUDE_DIR="$HOME/.claude"
CLAUDE_SETTINGS="$CLAUDE_DIR/settings.json"
HOOK_LINK="$CLAUDE_DIR/hooks/session-status.sh"
# How settings.json refers to the hook: the same string the README shows.
HOOK_COMMAND="~/.claude/hooks/session-status.sh"
# Claude Code events and the state the hook writes for each.
HOOK_EVENTS="SessionStart:idle UserPromptSubmit:busy PostToolUse:busy Notification:waiting Stop:idle SessionEnd:end"
# Offered by name if installed; any other app can be typed in.
KNOWN_BROWSERS="Arc|Safari|Google Chrome|Brave Browser|Microsoft Edge|Chromium|Vivaldi"
KNOWN_CLAUDE_APPS="Claude|Terminal|iTerm|Ghostty|Warp|WezTerm|kitty|Alacritty|Visual Studio Code|Cursor|Zed"

step() { printf '\n%s\n' "$*"; }
ok()   { echo "   ✓ $*"; }
bad()  { echo "   ✗ $*"; }
note() { echo "     $*"; }
# A path with $HOME shortened to ~, for messages.
short() { echo "${1/#$HOME/~}"; }

# Asks a yes/no question; an empty answer means the default (y or n).
# With ASSUME_YES (init --yes), takes the default without asking.
# Usage: ask_yes <question> [y|n]
ask_yes() {
  local default="${2:-y}" hint=y/N answer=""
  [ "$default" = y ] && hint=Y/n
  if [ -z "$ASSUME_YES" ]; then
    printf '   %s [%s] ' "$1" "$hint" >&2
    read -r answer
  fi
  case "${answer:-$default}" in
    [Yy]*) return 0 ;;
    *) return 1 ;;
  esac
}

# Asks to pick an option by number, or to type a value, which is checked with
# validate_setting. Prints the choice; an empty answer means the default.
# Options are "value|label". Usage: choose <key> <question> <default> <option>...
choose() {
  local key="$1" question="$2" default="$3" n=0 option answer error
  shift 3
  if [ -n "$ASSUME_YES" ]; then
    echo "$default"
    return
  fi
  echo "   $question" >&2
  for option in "$@"; do
    n=$((n + 1))
    printf '     %d) %s\n' "$n" "${option#*|}" >&2
  done
  while :; do
    answer=""
    printf '   number or name [%s]: ' "$default" >&2
    read -r answer
    if [ -z "$answer" ]; then
      echo "$default"
      return
    fi
    case "$answer" in
      *[!0-9]*) ;;
      *)
        if [ "$answer" -ge 1 ] && [ "$answer" -le $# ]; then
          option="${!answer}"
          echo "${option%%|*}"
          return
        fi ;;
    esac
    if error=$(validate_setting "$key" "$answer"); then
      echo "$answer"
      return
    fi
    echo "   $error" >&2
  done
}

# Asks for an app, offering the installed ones from a "|"-separated list.
# The default is the current setting if it's installed, else the first one
# offered. Usage: choose_app <key> <question> <current> <known apps>
choose_app() {
  local key="$1" question="$2" default="$3" app options=()
  local IFS='|'
  for app in $4; do
    app_exists "$app" && options+=("$app|$app")
  done
  unset IFS
  if ! app_exists "$default" && [ ${#options[@]} -gt 0 ]; then
    default="${options[0]%%|*}"
  fi
  choose "$key" "$question" "$default" "${options[@]}"
}

# Prints a path with symlinks resolved, to compare where two paths lead.
real_path() {
  local path="$1" link
  while [ -L "$path" ]; do
    link=$(readlink "$path")
    case "$link" in
      /*) path="$link" ;;
      *)  path="$(dirname "$path")/$link" ;;
    esac
  done
  echo "$(cd "$(dirname "$path")" 2>/dev/null && pwd -P)/$(basename "$path")"
}

# Links the command into a writable folder on the PATH. The link has to point
# at this checkout, since the command finds lib/ next to the file it leads to.
setup_command() {
  local target found dir="" candidate
  target="$(dirname "$LIB_DIR")/doomscroller"
  found=$(command -v doomscroller)
  if [ -n "$found" ] && [ "$(real_path "$found")" = "$(real_path "$target")" ]; then
    ok "doomscroller is on your PATH: $(short "$found")"
    return
  fi
  if [ -n "$found" ]; then
    bad "another doomscroller is on your PATH: $found"
    note "Replace it with a link to this one: ln -sf '$target' '$found'"
    return
  fi
  for candidate in /opt/homebrew/bin /usr/local/bin "$HOME/.local/bin" "$HOME/bin"; do
    case ":$PATH:" in
      *":$candidate:"*) [ -d "$candidate" ] && [ -w "$candidate" ] && { dir="$candidate"; break; } ;;
    esac
  done
  if [ -z "$dir" ]; then
    bad "no folder on your PATH that can be written without sudo"
    note "Link it yourself: sudo ln -s '$target' /usr/local/bin/doomscroller"
    return
  fi
  ask_yes "Link doomscroller into $(short "$dir")?" || return
  ln -s "$target" "$dir/doomscroller" && ok "linked $(short "$dir/doomscroller")"
}

# Links the hook script into ~/.claude/hooks. An existing file there is only
# replaced when you say so, and kept as .bak.
setup_hook_link() {
  local target
  target="$(dirname "$LIB_DIR")/hooks/session-status.sh"
  if [ -e "$HOOK_LINK" ] && [ "$(real_path "$HOOK_LINK")" = "$(real_path "$target")" ]; then
    ok "$(short "$HOOK_LINK") links here"
    return
  fi
  if [ -e "$HOOK_LINK" ] || [ -L "$HOOK_LINK" ]; then
    bad "$(short "$HOOK_LINK") exists and isn't doomscroller's hook"
    ask_yes "Replace it? The old one is kept as session-status.sh.bak" n || return
    mv "$HOOK_LINK" "$HOOK_LINK.bak"
  else
    ask_yes "Link the hook into $(short "$CLAUDE_DIR/hooks")?" || return
  fi
  mkdir -p "$(dirname "$HOOK_LINK")" && ln -s "$target" "$HOOK_LINK" && ok "linked $(short "$HOOK_LINK")"
}

# Succeeds if settings.json runs the hook with this state on this event.
# Any path to session-status.sh counts, so a hand-made entry isn't doubled.
# Usage: hook_registered <event> <state>
hook_registered() {
  [ -s "$CLAUDE_SETTINGS" ] &&
    jq -e --arg ev "$1" --arg state "$2" \
      'any(.hooks[$ev][]?.hooks[]?.command; endswith("session-status.sh " + $state))' \
      "$CLAUDE_SETTINGS" > /dev/null
}

# Adds the hook to ~/.claude/settings.json for every event that lacks it,
# keeping everything else in the file. The old file is kept as .bak.
setup_hook_settings() {
  local pair missing="" events="" tmp backup=""
  if ! command -v jq > /dev/null; then
    bad "jq not found, and the hook needs it. macOS 15 and later include it; otherwise: brew install jq"
    return
  fi
  if [ -s "$CLAUDE_SETTINGS" ] && ! jq empty "$CLAUDE_SETTINGS" 2> /dev/null; then
    bad "can't parse $(short "$CLAUDE_SETTINGS"). Add the hooks by hand (see the README)"
    return
  fi
  for pair in $HOOK_EVENTS; do
    if ! hook_registered "${pair%:*}" "${pair#*:}"; then
      missing="$missing $pair"
      events="$events, ${pair%:*}"
    fi
  done
  if [ -z "$missing" ]; then
    ok "$(short "$CLAUDE_SETTINGS") already runs the hook"
    return
  fi
  ask_yes "Add the hook to $(short "$CLAUDE_SETTINGS") for ${events#, }?" || return
  mkdir -p "$CLAUDE_DIR"
  tmp=$(mktemp "$CLAUDE_SETTINGS.XXXXXX")
  if [ -s "$CLAUDE_SETTINGS" ]; then
    cp "$CLAUDE_SETTINGS" "$CLAUDE_SETTINGS.bak"
    backup="$CLAUDE_SETTINGS.bak"
    cp "$CLAUDE_SETTINGS" "$tmp"
  else
    echo '{}' > "$tmp"
  fi
  for pair in $missing; do
    jq --arg ev "${pair%:*}" --arg cmd "$HOOK_COMMAND ${pair#*:}" \
      '.hooks[$ev] += [{hooks: [{type: "command", command: $cmd}]}]' "$tmp" > "$tmp.next" &&
      mv "$tmp.next" "$tmp"
  done
  # Written through rather than moved, so a settings.json that is a symlink
  # (say, into a dotfiles repo) stays one.
  cat "$tmp" > "$CLAUDE_SETTINGS" && rm -f "$tmp"
  ok "added the hook for ${events#, }"
  [ -n "$backup" ] && note "the previous settings are in $(short "$backup")"
  note "Claude Code sessions started from now on report their state; restart open ones"
}

# Asks for each setting, offering the current value as the default, and saves
# the answers to the config file.
setup_preferences() {
  local site browser app autoscroll=off
  site=$(choose site "Which feed?" "$SITE" "reels|Instagram Reels" "shorts|YouTube Shorts")
  browser=$(choose_app browser "Which browser should it open?" "$BROWSER" "$KNOWN_BROWSERS")
  app=$(choose_app claude-app "Which app should it bring back when Claude stops?" "$CLAUDE_APP" "$KNOWN_CLAUDE_APPS")
  local default=n
  [ "$AUTOSCROLL" = on ] && default=y
  ask_yes "Autoscroll: go to the next video when one ends?" "$default" && autoscroll=on
  save_setting site "$site"
  save_setting browser "$browser"
  save_setting claude-app "$app"
  save_setting autoscroll "$autoscroll"
  load_settings
  ok "saved: site $site, browser $browser, claude-app $app, autoscroll $autoscroll"
}

# Checks Accessibility (pressing keys) and Automation (the browser's tabs),
# and says what to switch on for Reels sound and autoscroll. Both permissions
# belong to the app this runs in, so run init where you'll run doomscroller.
setup_permissions() {
  if [ "$(osascript -l JavaScript "$LIB_DIR/jxa/is-trusted.js" 2> /dev/null)" = true ]; then
    ok "Accessibility is allowed"
  else
    bad "Accessibility isn't allowed for this app, so videos won't pause and Reels stay muted"
    note "Add the app you run doomscroller from, then restart that app"
    ask_yes "Open System Settings > Accessibility?" &&
      open "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
  fi

  if ! tab_script > /dev/null; then
    bad "$BROWSER can't be scripted: the page opens once, and Reels sound and autoscroll won't work"
    note "Supported: ${KNOWN_BROWSERS//|/, }"
    return
  fi
  if ask_yes "Check access to $BROWSER's tabs? macOS may ask you, and $BROWSER opens if it's closed"; then
    local result
    result=$(osascript -e "tell application \"$BROWSER\" to count windows" 2>&1)
    case "$result" in
      *-1743*)
        bad "Automation isn't allowed, so doomscroller can't reuse the tab or turn Reels sound on"
        note "Allow $BROWSER under this app in Automation"
        ask_yes "Open System Settings > Automation?" &&
          open "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation" ;;
      *[!0-9]*|"") bad "couldn't reach $BROWSER: $result" ;;
      *) ok "Automation for $BROWSER is allowed" ;;
    esac
  fi

  if [ "$SITE" = reels ] || [ "$AUTOSCROLL" = on ]; then
    case "$BROWSER" in
      Safari)
        note "For Reels sound and autoscroll, turn on Safari's Develop > Allow JavaScript from Apple Events" ;;
      Arc) ;;
      *)
        note "For Reels sound and autoscroll, turn on $BROWSER's View > Developer > Allow JavaScript from Apple Events" ;;
    esac
  fi
}

# Runs every step. Starting the watcher afterwards is up to the caller.
run_setup() {
  echo "Setting up doomscroller. Press Enter to take the answer in [brackets]."
  step "1. Command"
  setup_command
  step "2. Claude Code hook"
  setup_hook_link
  setup_hook_settings
  step "3. Preferences"
  setup_preferences
  step "4. Permissions"
  setup_permissions
}
