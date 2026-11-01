# Claude Code's state, read from the status file the hook keeps.
# Lines are tab-separated: state, time, session id, working directory.

# Prints "busy" if any session is busy, otherwise "idle" (waiting counts as idle).
claude_state() {
  if [ -f "$STATUS_FILE" ] && cut -f1 "$STATUS_FILE" | grep -qx busy; then
    echo busy
  else
    echo idle
  fi
}

# Prints every session's state with its folder name,
# e.g. "busy doomscroller, idle my-project".
session_states() {
  [ -f "$STATUS_FILE" ] || { echo "no sessions"; return; }
  awk -F'\t' '{ n = split($4, dir, "/"); printf "%s%s %s", (NR > 1 ? ", " : ""), $1, dir[n] }
              END { if (NR == 0) printf "no sessions"; print "" }' "$STATUS_FILE"
}

# Like claude_state, but tells waiting from idle: prints busy, waiting or idle.
claude_state_detail() {
  local states=""
  [ -f "$STATUS_FILE" ] && states=$(cut -f1 "$STATUS_FILE")
  if grep -qx busy <<< "$states"; then echo busy
  elif grep -qx waiting <<< "$states"; then echo waiting
  else echo idle
  fi
}

# Prints one line per session: its state and folder name, e.g. "busy doomscroller".
session_lines() {
  [ -f "$STATUS_FILE" ] || return
  awk -F'\t' '{ n = split($4, dir, "/"); print $1, dir[n] }' "$STATUS_FILE"
}
