# Commands: parses arguments, prints help and results. The work itself
# happens in the other modules.

usage() {
  cat <<EOF
doomscroller: watch Reels or Shorts while Claude Code works.

When Claude starts working, opens the page in $BROWSER. When it stops
(idle or waiting for you), pauses the video and brings $CLAUDE_APP back.

Usage:
  doomscroller init [--yes]
  doomscroller uninstall [--yes]
  doomscroller menubar [uninstall]
  doomscroller start [--reels | --shorts] [--autoscroll | --no-autoscroll] [--watch] [url]
  doomscroller stop
  doomscroller status
  doomscroller stats [--share]
  doomscroller config [list | get <key> | set <key> <value> | unset <key>]
  doomscroller --help | --version

Commands:
  init         set up: install the Claude Code hook, choose your feed, browser
               and apps, check permissions. Safe to run again
  uninstall    remove the hook from Claude Code, the settings and the log
  menubar      add a menu bar icon (SwiftBar or xbar) with Claude's state, an
               on/off switch and the feed; "menubar uninstall" removes it
  start        start watching in the background (log: ~/.doomscroller/log)
  stop         stop watching
  status       show whether it's running and what Claude is doing
  stats        how long you scrolled while Claude worked: today, the last 7
               days, all time. --share prints a line to post instead
  config       show or change settings (saved in ~/.doomscroller/config)

Flags for init and uninstall:
  -y, --yes    don't ask: take the answer in [brackets] everywhere

Flags for start:
  --reels      Instagram Reels, paused with the play/pause key (F8)
  --shorts     YouTube Shorts, paused with space
  --autoscroll, --no-autoscroll
               go to the next video when one ends, or don't (beats the config)
  -w, --watch  stay in this terminal and log Claude's state every second
  url          open this page instead, paused like the chosen site

Settings:
  site         reels or shorts (default: reels)
  browser      browser app (default: Arc)
  claude-app   app to return to (default: Claude; e.g. Terminal, iTerm, Ghostty)
  autoscroll   on or off: go to the next video when one ends (default: off)

  Examples: doomscroller config set site shorts
            doomscroller config set browser Google Chrome
            doomscroller config set autoscroll on
            doomscroller config unset browser

  For one run, environment variables override the config:
  DOOMSCROLLER_SITE, DOOMSCROLLER_BROWSER, DOOMSCROLLER_CLAUDE_APP,
  DOOMSCROLLER_AUTOSCROLL. Flags for start beat both.

Pausing presses keys, which needs Accessibility access for the app you run
doomscroller from (System Settings > Privacy & Security > Accessibility).
EOF
}

# doomscroller start [--reels | --shorts] [--autoscroll | --no-autoscroll] [--watch] [url]
cmd_start() {
  local arg watch_here="" custom_url=""
  for arg in "$@"; do
    case "$arg" in
      --reels) SITE=reels ;;
      --shorts) SITE=shorts ;;
      --autoscroll) AUTOSCROLL=on ;;
      --no-autoscroll) AUTOSCROLL=off ;;
      -w|--watch) watch_here=1 ;;
      -h|--help) usage; exit 0 ;;
      *) [ -n "$arg" ] && custom_url="$arg" ;;
    esac
  done
  use_site "$SITE"
  [ -n "$custom_url" ] && URL="$custom_url"
  if is_running; then
    echo "doomscroller is already running (pid $(cat "$PID_FILE"))"
    exit 0
  fi
  if [ -n "$watch_here" ]; then
    run_watcher_here
  else
    start_watcher
  fi
}

# Flags for init and uninstall: --yes, --help.
parse_setup_flags() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      -y|--yes) ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; exit 1 ;;
    esac
  done
}

# Prints the version, kept only in package.json.
version() {
  sed -n 's/^  "version": "\(.*\)",$/\1/p' "$(dirname "$LIB_DIR")/package.json"
}

# doomscroller init [--yes]
cmd_init() {
  parse_setup_flags "$@"
  run_setup
  step "6. Start"
  if is_running; then
    if ask_yes "doomscroller is running with the old settings. Restart it?"; then
      stop_watcher
      cmd_start
    fi
  elif ask_yes "Start doomscroller now?"; then
    cmd_start
  else
    echo "   Start it later with: doomscroller start"
  fi
}

# doomscroller uninstall [--yes]
cmd_uninstall() {
  parse_setup_flags "$@"
  echo "Removing doomscroller. Press Enter to take the answer in [brackets]."
  if is_running; then
    step "Watcher"
    printf '   '
    stop_watcher
  fi
  run_uninstall
}

# doomscroller menubar [uninstall]
cmd_menubar() {
  ASSUME_YES=1
  case "$1" in
    ""|install) setup_menubar ;;
    uninstall) uninstall_menubar ;;
    *) usage >&2; exit 1 ;;
  esac
}

# doomscroller stats [--share]
cmd_stats() {
  case "$1" in
    "") print_stats ;;
    --share) share_line ;;
    -h|--help) usage ;;
    *) usage >&2; exit 1 ;;
  esac
}

cmd_status() {
  if is_running; then
    echo "running (pid $(cat "$PID_FILE")), Claude is $(claude_state)"
  else
    echo "stopped, Claude is $(claude_state)"
  fi
}

# doomscroller config [list | get <key> | set <key> <value> | unset <key>]
cmd_config() {
  local action="${1:-list}" key="$2" value="${*:3}" info env default
  case "$action" in
    list|get|set|unset) ;;
    *) usage >&2; exit 1 ;;
  esac
  if [ "$action" != list ]; then
    if ! info=$(setting_info "$key"); then
      echo "unknown setting: '$key' (settings: $CONFIG_KEYS)" >&2
      exit 1
    fi
    read -r env default <<< "$info"
  fi
  case "$action" in
    list)
      for key in $CONFIG_KEYS; do
        printf '%-11s %s (%s)\n' "$key" "$(setting "$key")" "$(setting_source "$key")"
      done
      return ;;
    get)
      setting "$key"
      return ;;
    set)
      if [ -z "$value" ]; then
        echo "usage: doomscroller config set $key <value>" >&2
        exit 1
      fi
      validate_setting "$key" "$value" >&2 || exit 1
      save_setting "$key" "$value"
      echo "$key = $value" ;;
    unset)
      save_setting "$key"
      echo "$key = $default (default)" ;;
  esac
  # After set or unset: say when the change doesn't take effect right away.
  if [ -n "${!env}" ]; then
    echo "note: $env=${!env} is set in this shell and overrides the config"
  fi
  if is_running; then
    echo "doomscroller is running: restart it to apply (doomscroller stop, then start)"
  fi
}

main() {
  case "$1" in
    init)   cmd_init "${@:2}" ;;
    uninstall) cmd_uninstall "${@:2}" ;;
    start)  cmd_start "${@:2}" ;;
    stop)   stop_watcher ;;
    status) cmd_status ;;
    stats)  cmd_stats "${@:2}" ;;
    config) cmd_config "${@:2}" ;;
    menubar) cmd_menubar "${@:2}" ;;
    # The menu bar plugin: prints the menu, or handles a click on a setting.
    _menu)
      case "$2" in
        set)   menu_set "$3" "$4" ;;
        share) menu_share ;;
        *)     print_menu ;;
      esac ;;
    # The background watcher started by start_watcher.
    _watch)
      use_site "$2"
      AUTOSCROLL="$3"
      watch_claude "$4" ;;
    -h|--help|help) usage ;;
    -v|--version|version) version ;;
    *) usage >&2; exit 1 ;;
  esac
}
