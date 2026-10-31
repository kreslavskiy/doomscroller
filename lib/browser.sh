# The browser: finding the feed's tab, showing it, and running JavaScript in
# it. Tabs are driven with AppleScript, which needs Automation access to the
# browser. Supported: Arc, Safari and the Chrome family; other browsers fall
# back to plain `open`.

# Prints a URL's domain without "www.", e.g. "instagram.com".
url_host() {
  echo "$1" | sed -E 's#^[a-z]+://##; s#/.*##; s#^www\.##'
}

# Prints the page script lib/page/<name>.js.
page_js() {
  cat "$LIB_DIR/page/$1.js"
}

# AppleScript loops that pick the feed's tab: first a tab already on the
# feed, then any tab on the same site. So a YouTube video you're watching
# isn't taken over while a Shorts tab is open. Sets w and i to the tab.
# Tabs are addressed by index, so the same loop works in every browser.
FIND_TAB_START='repeat with pass from 1 to 2
    repeat with w in windows
      repeat with i from 1 to count of tabs of w
        set tab_url to (URL of tab i of w) as text
        if (pass = 1 and tab_url starts with target_url) or (pass = 2 and (tab_url contains ("://" & site_host & "/") or tab_url contains ("." & site_host & "/"))) then'
FIND_TAB_END='        end if
      end repeat
    end repeat
  end repeat'

# Prints an AppleScript for $BROWSER that looks for the feed's tab. If it
# finds one, it points the tab at the target URL (unless the tab is already
# there, so the current video isn't reloaded), brings it to the front and
# says "found"; otherwise it says "none". Each browser selects tabs its own
# way; fails for browsers without tab scripting.
tab_script() {
  local select_tab
  case "$BROWSER" in
    Arc) select_tab='select tab i of w' ;;
    Safari) select_tab='set current tab of w to tab i of w
          set index of w to 1' ;;
    "Google Chrome"|"Brave Browser"|"Microsoft Edge"|Chromium|Vivaldi)
      select_tab='set active tab index of w to i
          set index of w to 1' ;;
    *) return 1 ;;
  esac
  cat <<EOF
on run {site_host, target_url}
  tell application "$BROWSER"
    $FIND_TAB_START
          if tab_url does not start with target_url then set URL of tab i of w to target_url
          $select_tab
          activate
          return "found"
    $FIND_TAB_END
  end tell
  return "none"
end run
EOF
}

# Shows the page: reuses a tab already open on the same site, or opens a new one.
# If the browser's tabs can't be scripted (unsupported browser, or no Automation
# access), opens the page once and after that only brings the browser forward,
# so every turn doesn't add a new tab.
show_page() {
  local url="$1" host script result
  host=$(url_host "$url")
  if script=$(tab_script); then
    result=$(osascript - "$host" "$url" <<< "$script" 2>&1)
    case "$result" in
      found) log "switched to the $host tab"; return ;;
      none) open -a "$BROWSER" "$url"; PAGE_OPENED=1; return ;;
      *) log "can't read $BROWSER tabs: $result" ;;
    esac
  fi
  if [ -z "$PAGE_OPENED" ]; then
    open -a "$BROWSER" "$url"
    PAGE_OPENED=1
  else
    open -a "$BROWSER"
  fi
}

# Prints an AppleScript for $BROWSER that runs JavaScript in the feed's tab
# and returns the result, "no tab", or "timeout": while a page is still
# loading, Arc doesn't answer until it's done, which can take a minute.
# Fails for browsers without JavaScript scripting. Chrome-like browsers also
# need View > Developer > Allow JavaScript from Apple Events; Arc doesn't.
tab_js_script() {
  local run_js
  case "$BROWSER" in
    Safari) run_js='do JavaScript js in tab i of w' ;;
    Arc|"Google Chrome"|"Brave Browser"|"Microsoft Edge"|Chromium|Vivaldi)
      run_js='execute tab i of w javascript js' ;;
    *) return 1 ;;
  esac
  cat <<EOF
on run {site_host, target_url, js}
  tell application "$BROWSER"
    $FIND_TAB_START
          try
            with timeout of 2 seconds
              return $run_js
            end timeout
          on error number -1712
            return "timeout"
          end try
    $FIND_TAB_END
  end tell
  return "no tab"
end run
EOF
}

# Runs JavaScript in the tab of the feed at a URL and prints the result
# without the quotes Arc wraps it in. Every call runs in the page's global
# scope, so scripts are wrapped in a function. Usage: run_tab_js <url> <javascript>
run_tab_js() {
  local script
  script=$(tab_js_script) || return 1
  osascript - "$(url_host "$1")" "$1" "$2" <<< "$script" 2>&1 | tr -d '"'
}
