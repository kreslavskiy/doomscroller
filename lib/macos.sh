# macOS itself: apps and the keyboard. Pressing keys needs Accessibility
# access for the app that started doomscroller.

app_exists() {
  local dir
  for dir in /Applications /Applications/Utilities /System/Applications \
             /System/Applications/Utilities "$HOME/Applications"; do
    [ -d "$dir/$1.app" ] && return 0
  done
  return 1
}

# Name of the app in front, e.g. "Arc". lsappinfo needs no permissions.
frontmost_app() {
  lsappinfo info -only name "$(lsappinfo front)" | cut -d'"' -f4
}

# Presses a key in the frontmost app, by macOS key code (49 is space, 105 is F13).
press_key_code() {
  osascript -e "tell application \"System Events\" to key code $1" > /dev/null 2>&1
}

# Presses the media play/pause key, which is what F8 does on a Mac keyboard.
# See jxa/play-pause-key.js for why a plain F8 key code wouldn't work.
press_play_pause_key() {
  osascript -l JavaScript "$LIB_DIR/jxa/play-pause-key.js" > /dev/null 2>&1
}
