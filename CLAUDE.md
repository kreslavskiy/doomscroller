# CLAUDE.md

doomscroller opens Instagram Reels or YouTube Shorts in the browser while
Claude Code is busy. When Claude goes idle, it pauses the video and switches
back to Claude. It's a macOS-only bash CLI. See README.md for the user-facing
docs.

## Layout

- `doomscroller`: the whole CLI in a single bash script. It handles
  `start [--reels|--shorts] [-w] [url]`, `stop`, `status`, `config …` and
  `--help`, plus an internal `_watch <site> <url>` entry point that the
  background process runs.
- `hooks/session-status.sh`: the Claude Code hook. It writes
  `~/Desktop/claude-status.txt` with one tab-separated line per session:
  `state  time  session_id  cwd`. The state is `busy`, `waiting` or `idle`.
  `end` removes the line.

The installed copies are symlinks: `/opt/homebrew/bin/doomscroller` points to
`doomscroller`, and the hook is wired up in `~/.claude/settings.json`.
**Editing the files here changes the live tool.** A watcher that is already
running keeps the old code until it is restarted.

## How the watcher works

- It polls the status file every second. The aggregate state is `busy` if any
  line is `busy`. Everything else, including `waiting`, counts as idle.
- It acts only on transitions. It starts from `idle`, so if Claude is already
  busy at start, the first poll opens the page.
- busy: `show_page` runs a generated AppleScript (`tab_script`) that looks for
  a tab on the URL's domain (`url_host`). If it finds one, it sets the tab's
  URL to the target, unless the tab is already there, so the video isn't
  reloaded, then selects the tab. If no tab is found, it runs
  `open -a "$BROWSER" "$URL"`. If the browser can't be scripted (no
  `tab_script` case, or no Automation access), it opens the page once per
  run and afterwards only runs `open -a "$BROWSER"`.
- busy on Instagram: `unmute_reels` then turns the sound on in a freshly
  loaded page. It polls `REELS_CHECK_JS` until a reel is on screen, presses
  F13, runs `REELS_UNMUTE_JS`, then retries `REELS_PLAY_JS` until the reel
  plays. The `window.__doomscroller` mark limits this to once per page load.
- idle: it presses the site's pause key, but only if the browser is the
  frontmost app, then runs `open -a "$CLAUDE_APP"`.
- Settings are resolved per key: env var (`DOOMSCROLLER_SITE`, `_BROWSER`,
  `_CLAUDE_APP`), then `~/.doomscroller/config`, then the default. Defaults
  live in `setting_info`.

## Non-obvious decisions, keep them

- **Background start goes through `perl -MPOSIX -e 'setsid; exec @ARGV'`.**
  The Claude desktop app kills the whole process group of a `!` command, so
  without a new session the watcher dies with that shell. macOS has no
  `setsid` binary.
- **The Reels pause key is the media play/pause key, not the F8 key code.**
  F8 on a Mac keyboard sends `NX_KEYTYPE_PLAY` (16), which macOS routes to
  whatever is playing. `key code 100` sends a plain F8, which the page ignores.
  The JXA snippet in `PLAY_KEY_JS` posts the system-defined event. It checks
  `AXIsProcessTrusted()` first and throws without access, so failures show up
  in the log.
- **Keys are pressed only when the browser is in front** (`frontmost_app` via
  `lsappinfo`, which needs no permissions). Otherwise a space would be typed
  into whatever app the user switched to, for example Claude's prompt box.
- **Apps are validated by looking for `<name>.app` in the standard folders.**
  Don't use `open -Ra`, which reveals the app in Finder, or AppleScript
  `application "X"`, which can pop up a "Where is X?" dialog.
- **Tabs are addressed by index (`tab i of w`), not by `repeat with t in`
  references,** so the same script body works in Arc, Safari and Chromium
  browsers. Only the select line differs per browser. Check a new browser
  case with `osacompile`: it compiles against the app's dictionary without
  sending events, so no permission prompt appears.
- **Reels sound needs a real key press first.** Chromium allows unmuted
  playback only after user activation. Clicks made from JavaScript don't
  count, and neither does `execute` from AppleScript. A System Events key
  press does count. F13 is used because it types nothing and Instagram
  ignores it. Without activation, unmuting works, but `play()` rejects with
  `NotAllowedError`. This was verified live in Arc.
- **Use Instagram's own controls, not the `<video>` element.** Clicking the
  `Audio is muted` button makes Instagram keep sound on for later reels.
  Calling `video.play()` directly gets undone, because Instagram still
  thinks the reel is paused and pauses it again. So the script clicks the
  `Press to play` overlay instead.
- **Arc's `execute` blocks while a page loads,** sometimes for over a minute,
  which used to freeze the watcher. `tab_js_script` wraps it in
  `with timeout of 2 seconds` and returns `"timeout"`, and callers retry.
  Also, every `execute` runs in the page's global scope, so wrap the JS in
  an IIFE: a second top-level `const` fails and returns `null`. Results come
  back JSON-quoted, and `run_tab_js` strips the quotes.
- Pressing keys needs Accessibility access, and reading tabs needs Automation
  access to the browser. Both are granted to the *responsible* app, meaning
  the one the user launched doomscroller from, not doomscroller itself.

## Conventions

- Target the system `/bin/bash`, which is **3.2**: no `mapfile`, no
  associative arrays, no `${var,,}`. Use only macOS built-ins (`open`,
  `osascript`, `lsappinfo`, `perl`, `awk`, `jq` for the hook). No installs.
- Short functions, each with a one-line comment saying what it does or why.
  Comments and user-facing text are in English.
- When you add a command, flag or setting, update `usage()` and README.md in
  the same change. `usage()` is the single source for the CLI reference.
- Errors go to stderr and exit 1. Help and success output go to stdout and
  exit 0.

## Testing

There is no test suite. Exercise the script in isolation, and **never switch
windows or press keys on the real desktop** while the user is working:

- Point it at a fake status file: `DOOMSCROLLER_STATUS_FILE=/tmp/…/status.txt`.
- Use a throwaway `HOME=…` so the real `~/.doomscroller` (pid, config, log) is
  untouched. A real watcher may be running.
- Put stub `open`, `osascript` and `lsappinfo` scripts first in `PATH`. Have
  them append their arguments to a file, and return a fake frontmost app for
  `lsappinfo`.
- Rewrite the fake status file to drive transitions, sleep about 1.5 s between
  steps, then check the stub calls and `$HOME/.doomscroller/log`.
- Run `bash -n doomscroller` for a syntax check.
- Page-side JavaScript (`REELS_*_JS`) can only be tested live. Run it
  through `run_tab_js` against the user's real tab. Read-only probes are
  fine. Ask before anything that reloads, pauses or unmutes. The agent's
  shell has no Accessibility access, so the F13 step can only be tested by
  the user.
- To call a single function, use
  `bash -c 'eval "$(sed -n "/^name()/,/^}/p" doomscroller)"; name …'`.
  bash 3.2 can't `source <(…)`.

The Bash tool's shell is zsh: unquoted `$args` doesn't word-split, and
`echo ===` fails. Pass arguments explicitly in test loops.
