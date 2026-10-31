# The video in the feed: pausing it, turning Reels sound on, and autoscroll.

# Presses the site's pause key: space, or the media play/pause key.
press_pause_key() {
  case "$PAUSE_KEY" in
    space) press_key_code 49 ;;
    play)  press_play_pause_key ;;
  esac
}

# Pauses the video, but only if the browser is still in front: otherwise
# the key would land in whatever app you switched to.
pause_video() {
  [ "$(frontmost_app)" = "$BROWSER" ] || return
  if press_pause_key; then
    log "paused video ($PAUSE_KEY key)"
    sleep 0.2
  else
    log "can't press keys: allow Accessibility in System Settings > Privacy & Security"
  fi
}

# Turns the sound on in a freshly loaded Reels page. The browser allows sound
# only after the user has interacted with the page, so it first presses F13:
# a key that types nothing and that Instagram ignores, but that the browser
# counts as interaction. Clicks made from JavaScript don't count.
unmute_reels() {
  local url="$1" state="" result deadline=$((SECONDS + 15))
  [ "$(url_host "$url")" = instagram.com ] || return
  # Wait up to 15 s for the page to load and show a reel.
  while [ $SECONDS -lt $deadline ]; do
    state=$(run_tab_js "$url" "$(page_js reels-check)") || return
    [ "$state" = loading ] || [ "$state" = timeout ] || break
    sleep 0.5
  done
  case "$state" in
    muted) ;;
    skip|loading|timeout|"no tab") return ;;
    *) log "can't run JavaScript in $BROWSER: $state"; return ;;
  esac
  [ "$(frontmost_app)" = "$BROWSER" ] || return
  press_key_code 105 \
    || log "can't press keys: allow Accessibility in System Settings > Privacy & Security"
  result=$(run_tab_js "$url" "$(page_js reels-unmute)")
  # Make sure the reel plays: a second later Instagram may have paused it.
  local tries=0 playing=""
  while [ $tries -lt 3 ] && [ "$playing" != playing ]; do
    sleep 1
    playing=$(run_tab_js "$url" "$(page_js reels-play)")
    tries=$((tries + 1))
  done
  log "turned on Reels sound ($result, video $playing)"
}

# Installs autoscroll (lib/page/autoscroll.js) in the feed's tab. Right after
# opening or redirecting the tab, the old page may still be there or the new
# one may still load, so it retries for up to 15 s.
start_autoscroll() {
  local url="$1" state deadline=$((SECONDS + 15))
  local js
  js="$(page_js autoscroll)(\"$url\", \"${NEXT_BUTTON//\"/\\\"}\")"
  while [ $SECONDS -lt $deadline ]; do
    if ! state=$(run_tab_js "$url" "$js"); then
      log "autoscroll needs a browser that runs JavaScript from AppleScript"
      return
    fi
    case "$state" in
      on) log "autoscroll on"; return ;;
      "already on"|"no tab") return ;;
      timeout|"wrong page") sleep 0.5 ;;
      *) log "can't start autoscroll: $state"; return ;;
    esac
  done
}
