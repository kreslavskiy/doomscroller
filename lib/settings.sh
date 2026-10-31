# Settings: each one comes from its environment variable, then the config
# file (key=value lines in $CONFIG_FILE), then its default.

CONFIG_KEYS="site browser claude-app autoscroll"

# Prints a setting's environment variable and default, e.g. "DOOMSCROLLER_SITE reels".
setting_info() {
  case "$1" in
    site)       echo "DOOMSCROLLER_SITE reels" ;;
    browser)    echo "DOOMSCROLLER_BROWSER Arc" ;;
    claude-app) echo "DOOMSCROLLER_CLAUDE_APP Claude" ;;
    autoscroll) echo "DOOMSCROLLER_AUTOSCROLL off" ;;
    *) return 1 ;;
  esac
}

# Prints the value saved in the config file, empty if none.
config_value() {
  [ -f "$CONFIG_FILE" ] || return
  awk -v key="$1" 'index($0, key "=") == 1 { value = substr($0, length(key) + 2) } END { print value }' "$CONFIG_FILE"
}

# Prints where a setting comes from: env, config or default.
setting_source() {
  local env default
  read -r env default <<< "$(setting_info "$1")"
  if [ -n "${!env}" ]; then echo env
  elif [ -n "$(config_value "$1")" ]; then echo config
  else echo default
  fi
}

# Prints a setting's current value.
setting() {
  local env default
  read -r env default <<< "$(setting_info "$1")"
  case "$(setting_source "$1")" in
    env)     echo "${!env}" ;;
    config)  config_value "$1" ;;
    default) echo "$default" ;;
  esac
}

# Sets the globals the rest of the app reads. Flags for start may change
# SITE and AUTOSCROLL afterwards.
load_settings() {
  SITE=$(setting site)
  BROWSER=$(setting browser)
  CLAUDE_APP=$(setting claude-app)
  AUTOSCROLL=$(setting autoscroll)
}

# Checks a value before it's saved; says what's wrong if it isn't valid.
validate_setting() {
  case "$1" in
    site)
      [ "$2" = reels ] || [ "$2" = shorts ] || { echo "site must be reels or shorts"; return 1; } ;;
    autoscroll)
      [ "$2" = on ] || [ "$2" = off ] || { echo "autoscroll must be on or off"; return 1; } ;;
    browser|claude-app)
      app_exists "$2" || { echo "app not found: $2.app (looked in /Applications, ~/Applications and /System/Applications)"; return 1; } ;;
  esac
}

# Writes key=value to the config file, or removes the key if no value is given.
save_setting() {
  mkdir -p "$STATE_DIR"
  local tmp
  tmp=$(mktemp "$CONFIG_FILE.XXXXXX")
  [ -f "$CONFIG_FILE" ] && grep -v "^$1=" "$CONFIG_FILE" > "$tmp"
  [ -n "$2" ] && echo "$1=$2" >> "$tmp"
  mv "$tmp" "$CONFIG_FILE"
}
