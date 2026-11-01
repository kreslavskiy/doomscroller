# The watcher process: follows Claude's state and switches between the feed
# and Claude. One instance at a time, tracked by $PID_FILE.

is_running() {
  [ -f "$PID_FILE" ] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null
}

# Polls Claude's state every second. The feed opens once Claude has been
# busy for $DELAY seconds and you're in $CLAUDE_APP: if you switched to
# another app, it stays out of your way. When Claude stops, it brings you
# back from the feed, or notifies you if you're somewhere else.
# With "verbose", also logs every poll. Usage: watch_claude <url> [verbose]
watch_claude() {
  local url="$1" verbose="$2" now front since_poll
  # The busy turn: its day and start, $SECONDS when it began and at the last
  # poll, the seconds the feed was in front (for stats), whether the feed is
  # shown, and whether the log already says why it isn't.
  local turn_day="" turn_start turn_began last_poll scrolled shown held
  # Stopping in the middle of a turn still records it.
  trap '[ -n "$turn_day" ] && stats_record "$turn_day" "$turn_start" $((SECONDS - turn_began)) "$scrolled"; exit 0' TERM INT
  log "watching, Claude is $(claude_state)"
  local last=idle
  while sleep 1; do
    now=$(claude_state)
    [ -n "$verbose" ] && log "$now | $(session_states)"

    if [ "$now" = busy ]; then
      if [ "$last" != busy ]; then
        log "busy"
        turn_day=$(date +%F) turn_start=$(date +%s) turn_began=$SECONDS last_poll=$SECONDS
        scrolled=0 shown="" held=""
      fi
      # Elapsed time, not one per poll: a poll can block for seconds while
      # the feed opens.
      since_poll=$((SECONDS - last_poll)) last_poll=$SECONDS
      front=$(frontmost_app)
      if [ -n "$shown" ]; then
        [ "$front" = "$BROWSER" ] && scrolled=$((scrolled + since_poll))
      elif [ $((SECONDS - turn_began)) -ge "$DELAY" ]; then
        if [ "$front" = "$CLAUDE_APP" ]; then
          log "busy -> $BROWSER"
          show_page "$url"
          unmute_reels "$url"
          [ "$AUTOSCROLL" = on ] && start_autoscroll "$url"
          shown=1
        elif [ -z "$held" ]; then
          log "busy, but you're in ${front:-another app}: not opening the feed"
          held=1
        fi
      fi
      stats_update "$turn_day" "$turn_start" $((SECONDS - turn_began)) "$scrolled"

    elif [ "$last" = busy ]; then
      front=$(frontmost_app)
      if [ "$front" = "$CLAUDE_APP" ]; then
        log "$now, you're already in $CLAUDE_APP"
      elif [ -n "$shown" ] && [ "$front" = "$BROWSER" ]; then
        log "$now -> $CLAUDE_APP"
        pause_video
        open -a "$CLAUDE_APP"
      else
        log "$now, you're in ${front:-another app}: notified"
        if [ "$(claude_state_detail)" = waiting ]; then
          notify "Claude needs you" "It's waiting for your answer"
        else
          notify "Claude is done" "Your turn"
        fi
      fi
      stats_record "$turn_day" "$turn_start" $((SECONDS - turn_began)) "$scrolled"
      turn_day=""
    fi
    last=$now
  done
}

# Runs the watcher in this terminal, logging every poll, until Ctrl+C.
run_watcher_here() {
  mkdir -p "$STATE_DIR"
  echo $$ > "$PID_FILE"
  trap 'rm -f "$PID_FILE"' EXIT
  echo "doomscroller watching: $URL in $BROWSER, autoscroll $AUTOSCROLL (Ctrl+C to stop)"
  watch_claude "$URL" verbose
}

# Starts the watcher in the background, logging to $LOG_FILE. It re-runs this
# command as `doomscroller _watch <site> <autoscroll> <url>`.
start_watcher() {
  mkdir -p "$STATE_DIR"
  # setsid puts the watcher in its own session, so it survives the shell
  # that started it (the Claude app kills a `!` command's whole group).
  # macOS has no setsid command, hence the perl one-liner.
  nohup perl -MPOSIX -e 'setsid; exec @ARGV' "$DOOMSCROLLER" _watch "$SITE" "$AUTOSCROLL" "$URL" \
    >> "$LOG_FILE" 2>&1 < /dev/null &
  echo $! > "$PID_FILE"
  echo "doomscroller started: $URL in $BROWSER, autoscroll $AUTOSCROLL"
}

# Prints the site and autoscroll the running watcher was started with, e.g.
# "shorts off", read from its `_watch` arguments (flags for start may differ
# from the config).
watcher_settings() {
  ps -o args= -p "$(cat "$PID_FILE")" 2> /dev/null |
    awk '{ for (i = 1; i < NF; i++) if ($i == "_watch") { print $(i + 1), $(i + 2); exit } }'
}

stop_watcher() {
  if is_running; then
    kill "$(cat "$PID_FILE")"
    echo "doomscroller stopped"
  else
    echo "doomscroller is not running"
  fi
  rm -f "$PID_FILE"
}
