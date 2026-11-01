# The menu bar menu, for a SwiftBar or xbar plugin: Claude's state, whether
# doomscroller is running, and items to start, stop and change the feed.
# The plugin itself is a stub that runs `doomscroller _menu` (setup.sh writes
# it), so the menu updates with the package. Clicking an item runs
# doomscroller again with the item's arguments.

# Prints the title: an SF Symbol in SwiftBar (which sets $SWIFTBAR), an emoji
# in xbar, then the text if any. Usage: menu_icon <sf symbol> <emoji> [text]
menu_icon() {
  if [ -n "$SWIFTBAR" ]; then
    echo "${3:+$3 }| sfimage=$1"
  else
    echo "$2${3:+ $3}"
  fi
}

# Prints an item that runs doomscroller with these arguments when clicked,
# then refreshes the menu. Usage: menu_item <text> <arg>...
menu_item() {
  local text="$1" n=1 arg params=""
  shift
  for arg in "$@"; do
    params="$params param$n=\"$arg\""
    n=$((n + 1))
  done
  echo "$text | bash=\"$DOOMSCROLLER\"$params terminal=false refresh=true"
}

# Like menu_item, with a checkmark when the first argument is "on". SwiftBar
# draws real checkmarks; xbar gets a ✓ in the text.
# Usage: menu_choice <on|off> <text> <arg>...
menu_choice() {
  local checked="$1" text="$2" line
  shift 2
  if [ "$checked" = on ] && [ -z "$SWIFTBAR" ]; then
    text="✓ $text"
  fi
  line=$(menu_item "$text" "$@")
  if [ "$checked" = on ] && [ -n "$SWIFTBAR" ]; then
    line="$line checked=true"
  fi
  echo "$line"
}

# Prints "on" if the two arguments are equal, else "off".
on_if() {
  if [ "$1" = "$2" ]; then echo on; else echo off; fi
}

# Prints the whole menu in the SwiftBar/xbar format: the title, then items
# separated by "---"; a "--" prefix puts an item in a submenu.
print_menu() {
  local state site="$SITE" autoscroll="$AUTOSCROLL" running="" sessions line
  local turns busy scrolled videos today=""
  state=$(claude_state_detail)
  read -r turns busy scrolled videos <<< "$(stats_sum "$(date +%F)")"
  # Today's scrolling, next to the icon.
  [ "$scrolled" -gt 0 ] && today=$(fmt_duration "$scrolled")
  if is_running; then
    running=1
    # Show what the watcher really uses, which flags for start may have changed.
    read -r site autoscroll <<< "$(watcher_settings)"
    site=${site:-$SITE} autoscroll=${autoscroll:-$AUTOSCROLL}
  fi

  if [ -z "$running" ]; then
    menu_icon play.slash ⏹ "$today"
  else
    case "$state" in
      busy)    menu_icon play.rectangle.fill 🍿 "$today" ;;
      waiting) menu_icon hand.raised.fill ✋ "$today" ;;
      *)       menu_icon play.rectangle 💤 "$today" ;;
    esac
  fi
  echo "---"

  sessions=$(session_lines)
  if [ -z "$sessions" ]; then
    echo "No Claude Code sessions"
  else
    case "$state" in
      busy)    echo "Claude is working" ;;
      waiting) echo "Claude is waiting for you" ;;
      *)       echo "Claude is idle" ;;
    esac
    while read -r line; do
      echo "--${line#* }: ${line%% *}"
    done <<< "$sessions"
  fi
  echo "---"

  print_menu_stats "$busy" "$scrolled" "$videos"
  echo "---"

  if [ -n "$running" ]; then
    echo "doomscroller is on: $(site_name "$site") in $BROWSER"
    menu_item "Turn off" stop
  else
    echo "doomscroller is off"
    menu_item "Turn on" start
  fi
  echo "---"

  menu_choice "$(on_if "$site" reels)" "Instagram Reels" _menu set site reels
  menu_choice "$(on_if "$site" shorts)" "YouTube Shorts" _menu set site shorts
  if [ "$autoscroll" = on ]; then
    menu_choice on "Autoscroll" _menu set autoscroll off
  else
    menu_choice off "Autoscroll" _menu set autoscroll on
  fi
  echo "---"
  if [ -f "$LOG_FILE" ]; then
    echo "Open log | bash=/usr/bin/open param1=-t param2=\"$LOG_FILE\" terminal=false"
  fi
}

# Prints the stats part of the menu: today, the last 7 days, the best day.
# Usage: print_menu_stats <busy today> <scrolled today> <videos today>
print_menu_stats() {
  local busy="$1" scrolled="$2" videos="$3" week best_day best
  if [ -z "$(stats_lines)" ]; then
    echo "No stats yet"
    return
  fi
  echo "Today: scrolled $(fmt_duration "$scrolled"), ≈ $videos videos"
  if [ "$busy" -gt 0 ]; then
    echo "--Claude worked $(fmt_duration "$busy"), you scrolled $(percent "$scrolled" "$busy") of it"
  fi
  read -r _ _ week _ <<< "$(stats_sum $(last_days 7))"
  echo "Last 7 days: $(fmt_duration "$week")"
  read -r best_day best <<< "$(stats_best_day)"
  if [ "$best_day" = "$(date +%F)" ] && [ "$(stats_first_day)" != "$best_day" ]; then
    echo "New record today! 🏆"
  elif [ -n "$best_day" ]; then
    echo "Best day: $(fmt_day "$best_day"), $(fmt_duration "$best")"
  fi
  echo "Show all stats | bash=\"$DOOMSCROLLER\" param1=stats terminal=true"
  menu_item "Copy for sharing" _menu share
}

# A menu click on "Copy for sharing": puts share_line on the clipboard and
# says so in a notification.
menu_share() {
  local line
  line=$(share_line) || return
  # pbcopy reads its input in the locale's encoding, and SwiftBar runs
  # plugins without LANG, which means MacRoman: "≈" would turn into "‚âà".
  printf '%s' "$line" | LANG=en_US.UTF-8 pbcopy
  osascript -e 'display notification "Paste it anywhere" with title "doomscroller stats copied"' > /dev/null 2>&1
}

# A menu click that changes a setting: saves it, and restarts the watcher if
# it's running so the change applies at once. Usage: menu_set <key> <value>
menu_set() {
  validate_setting "$1" "$2" > /dev/null || return 1
  save_setting "$1" "$2"
  load_settings
  if is_running; then
    stop_watcher > /dev/null
    use_site "$SITE"
    start_watcher > /dev/null
  fi
}
