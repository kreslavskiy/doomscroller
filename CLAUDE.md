# CLAUDE.md

doomscroller opens Instagram Reels or YouTube Shorts in the browser while
Claude Code is busy. When Claude goes idle, it pauses the video and switches
back to Claude. It's a macOS-only bash CLI. See README.md for the user-facing
docs.

## Architecture

```
hooks/session-status.sh ──▶ ~/.doomscroller/claude-status ──▶ doomscroller (watcher) ──▶ browser tab / Claude app
   (Claude Code hook)            (one line per session)        polls every second
```

```
doomscroller            entry point: finds lib/ (following the symlink), sources the modules, calls main
lib/
  core.sh               paths (STATUS_FILE, STATE_DIR, PID/LOG/CONFIG_FILE, HISTORY/CURRENT_FILE) and log()
  settings.sh           settings: env var > config file > default; load_settings, validate, save
  sites.sh              use_site: per-feed URL, PAUSE_KEY, NEXT_BUTTON
  claude.sh             reads the status file: claude_state, session_states
  macos.sh              apps and keyboard: app_exists, frontmost_app, press_key_code, press_play_pause_key
  browser.sh            AppleScript for tabs: show_page (find/reuse/open the tab), run_tab_js, page_js
  player.sh             the video: pause_video, unmute_reels, start_autoscroll
  stats.sh              scroll stats: record turns (stats_update, stats_record), sum them (stats_sum), print_stats, share_line
  watcher.sh            the process: watch_claude loop, start_watcher (background), run_watcher_here (-w), stop_watcher
  menubar.sh            the SwiftBar/xbar menu: print_menu (icon, sessions, on/off, feed, autoscroll), menu_set (a click on a setting)
  setup.sh              init (put the command on PATH, copy the hook, merge it into ~/.claude/settings.json, ask preferences, check permissions, add the menu bar plugin) and uninstall
  cli.sh                usage, version, cmd_init/cmd_uninstall/cmd_menubar/cmd_start/cmd_status/cmd_config, main (command dispatch)
  page/*.js             JavaScript run inside the feed's tab (via run_tab_js)
    reels-check.js        is a reel on screen, and does it need sound?
    reels-unmute.js       click Instagram's sound button
    reels-play.js         click Instagram's "Press to play" if the reel is paused
    autoscroll.js         a function; installs the "next video when this one ends" listener
  jxa/play-pause-key.js JavaScript for Automation, run by osascript: posts the media play/pause key
  jxa/is-trusted.js     prints whether the running app has Accessibility access (for init)
hooks/session-status.sh the Claude Code hook (see below)
package.json            the npm package: name, version (the only place it's kept), bin, files
```

### Layers and dependencies

Modules only define functions and constants. Nothing runs when a module is
sourced, apart from the constants in `core.sh`, `settings.sh`, `browser.sh`
and `setup.sh`. The entry point sources them in a fixed order
(`core settings sites claude macos browser player stats watcher menubar setup cli`), then runs
`load_settings` and `main "$@"`.

Calls go downward only:

- `cli` → `setup`, `menubar`, `stats`, `watcher`, `settings`, `sites`, `claude`
- `menubar` → `stats`, `watcher` (`is_running`, `watcher_settings`, start/stop), `settings`, `sites`, `claude`
- `setup` → `settings`, `browser` (`tab_script`, to tell if the browser is scriptable), `macos`
- `watcher` → `stats`, `browser`, `player`, `claude`
- `stats` → `sites` (`site_video_seconds`)
- `player` → `browser`, `macos`
- `browser` → `core`
- `settings` → `macos` (`app_exists`)

`claude.sh` knows nothing about the browser. `browser.sh` knows nothing about
Reels or Shorts. Site-specific knowledge lives in `sites.sh` (data) and in
`player.sh` with `page/` (behavior).

### Global state

Set once, then read by everyone:

| Variable | Set by | Meaning |
|----------|--------|---------|
| `DOOMSCROLLER`, `LIB_DIR` | entry point | the command as it was run (the watcher re-runs it); the `lib/` path |
| `SITE`, `BROWSER`, `CLAUDE_APP`, `AUTOSCROLL` | `load_settings`; `cmd_start` flags override `SITE`/`AUTOSCROLL` | settings |
| `URL`, `PAUSE_KEY`, `NEXT_BUTTON` | `use_site`; a `url` argument overrides `URL` | the feed |
| `PAGE_OPENED` | `show_page` | fallback: the page was already opened once this run |

### Commands

`init [--yes]`, `uninstall [--yes]`,
`start [--reels|--shorts] [--autoscroll|--no-autoscroll] [-w] [url]`, `stop`,
`status`, `stats [--share]`, `menubar [uninstall]`, `config [list|get|set|unset]`, `--help` and `--version`. There is also an
internal `_watch <site> <autoscroll> <url>`. `start_watcher` re-runs the
command with it as the background process, passing the already-resolved
settings so flags survive.

`init` runs `run_setup` (setup.sh), then `cmd_init` offers to start or
restart the watcher, since starting lives in cli. Each step checks first and
prints ✓ if there's nothing to do, so it's safe to re-run. Rules for it:

- Ask (`ask_yes`) before touching anything outside `~/.doomscroller`.
  Replacing a file someone else put there defaults to "no" and keeps a `.bak`.
- Never run `sudo`. Print the command instead.
- The settings.json merge goes through `jq`, adds only the missing events,
  and treats any command ending in `session-status.sh <state>` as already
  there. It writes through the file (`cat >`), so a symlinked settings.json
  stays a symlink.
- Prompts go to stderr, because `choose` prints the answer on stdout to be
  captured. `ASSUME_YES` (`--yes`) takes every default without reading stdin.
- `HOOK_COMMAND` and `HOOK_EVENTS` must match the JSON snippet in README.md.
- **The hook is copied, not linked.** npm replaces or deletes the package
  on update or uninstall, and a link into it would break every Claude
  session's hooks. `init` recognizes its own hook by the
  `doomscroller/claude-status` path inside it and offers to update an older
  copy. A link to the running checkout also counts as installed (that's
  how the dev setup works).
- `uninstall` (`cmd_uninstall`, then `run_uninstall`) undoes `init`: it
  stops the watcher, removes every hook command matching `OUR_HOOK_COMMAND`
  from settings.json (dropping events left empty), deletes the hook if it's
  ours and deletes `~/.doomscroller`. An npm-installed command belongs to
  npm, so it only prints `npm uninstall -g`.

### The menu bar plugin

`doomscroller menubar` (or step 5 of `init`) writes `doomscroller.2s.sh`
into SwiftBar's plugin folder (`defaults read com.ameba.SwiftBar
PluginDirectory`) or xbar's. The app reruns it every 2 seconds. It's a stub
that `exec`s the command with an absolute path, because the menu bar app's
PATH may not have it, and runs the internal `_menu`, so the menu itself
lives in `menubar.sh` and updates with the package. Each item runs the
command again (`bash=` with `param1=`…) with `start`, `stop` or
`_menu set <key> <value>`, which saves the setting and restarts a running
watcher.

- The title is today's scrolled time next to the icon. The stats part of
  the menu is `print_menu_stats`. "Copy for sharing" runs `_menu share`,
  which pipes `share_line` to `pbcopy` and shows a notification. `pbcopy`
  gets `LANG=en_US.UTF-8`: SwiftBar runs plugins without a locale, and
  `pbcopy` then reads MacRoman and garbles `≈` and emoji.
- SwiftBar sets `$SWIFTBAR`: the title is an SF Symbol (`sfimage=`) and
  checkmarks are `checked=true`. xbar gets emoji and a ✓ in the text.
- While the watcher runs, the menu shows its real site and autoscroll, read
  from its `_watch` arguments with `ps` (`watcher_settings`), since flags
  for start can differ from the config.
- A watcher started from the menu has SwiftBar as its responsible app, so
  SwiftBar needs Accessibility and Automation.
- It can't be tested here without SwiftBar. Run `doomscroller _menu`
  (with and without `SWIFTBAR=1`) and check the output format instead.

### The hook

`hooks/session-status.sh <busy|waiting|idle|end>` gets the hook JSON on
stdin. It keeps `~/.doomscroller/claude-status` (creating the folder if
needed) with one tab-separated line per session:
`state  time  session_id  cwd`. `end` removes the line. The path is written
both in the hook and in `STATUS_FILE` (core.sh): change them together.
`init` adds this wiring for you (see Commands). A `mkdir` lock
protects the file from parallel sessions, and it is replaced atomically. It is
wired to SessionStart/Stop (idle), UserPromptSubmit/PostToolUse (busy),
Notification (waiting) and SessionEnd (end) in `~/.claude/settings.json`.

### Installed copies are symlinks

On the user's machine, `/opt/homebrew/bin/doomscroller` points to
`doomscroller`, and `~/.claude/hooks/session-status.sh` points to
`hooks/session-status.sh` (set up by hand; `init` copies the hook instead
but accepts this link). **Editing the files here changes the live tool.** A
watcher that is already running keeps the old code until it is restarted.

### Releasing to npm

The package is `@kreslavskiy/doomscroller` on npm: plain `doomscroller` was
refused as too close to an existing `doom-scroller`. The command is still
`doomscroller`, because that's the `bin` name. Users run `npm install -g
@kreslavskiy/doomscroller`. `publishConfig.access` is `public`, since scoped
packages are private by default. npm links its `bin` to `doomscroller`, and the entry point
follows that link to `lib/`. `files` in package.json limits what ships to
`doomscroller`, `lib/` and `hooks/` (plus README.md and package.json).

1. Bump `version` in package.json, the only place it lives. `--version`
   reads it from there, so keep the `  "version": "x.y.z",` line format.
2. Check what ships: `npm pack --dry-run`. To test an install without
   touching the real one, use `npm i -g <tarball> --prefix <tmp>` and a
   throwaway `HOME`.
3. Commit, tag `vX.Y.Z`, push with tags, and run `npm publish`.
   `prepublishOnly` runs `npm test`, which is `bash -n` on every script.

## How the watcher works

- `watch_claude` polls `claude_state` every second. The aggregate state is
  `busy` if any line is `busy`. Everything else, including `waiting`, counts
  as idle. It starts from `idle`, so if Claude is already busy at start, the
  first polls count as a new turn.
- **busy** (every poll of a turn, until the feed is shown): once the turn is
  `$DELAY` seconds old and `frontmost_app` is `$CLAUDE_APP`, it shows the
  feed (the steps below) and sets `shown`. If another app is in front, it
  logs that once (`held`) and keeps checking, so coming back to Claude
  mid-turn opens the feed. The delay also keeps quick replies from flashing
  the browser.
  1. `show_page` runs `tab_script`. It picks the feed's tab with
     `FIND_TAB_START`: first a tab whose URL starts with the feed URL, then
     any tab on the domain. It points that tab at the feed unless it's
     already there, so the video isn't reloaded, and selects it. With no tab,
     it opens a new one. If the browser can't be scripted, it opens the page
     once per run and afterwards only brings the browser forward.
  2. `unmute_reels`, on Instagram only: polls `reels-check.js` until a reel
     is on screen, presses F13, runs `reels-unmute.js`, then retries
     `reels-play.js` until the reel plays. The `window.__doomscroller` mark
     limits this to once per page load.
  3. `start_autoscroll`, if `AUTOSCROLL=on`: injects `autoscroll.js` with the
     feed URL and `NEXT_BUTTON`, once per page load
     (`window.__doomscrollerScroll`). From then on, the page itself clicks
     "next" whenever the on-screen video finishes. Bash doesn't poll for it.
- **idle** (busy → idle): depends on the frontmost app. `$CLAUDE_APP`: do
  nothing. The browser, with the feed shown this turn: `pause_video`, then
  `open -a "$CLAUDE_APP"`. Anything else: `notify` ("Claude is done", or
  "Claude needs you" when `claude_state_detail` is `waiting`) and don't
  switch. `pause_video` itself still checks the browser is in front.
- **Stats**: every busy turn is recorded. On idle → busy the loop notes the
  day, the start time and `$SECONDS`. On each busy poll it adds the seconds
  since the last poll to `scrolled` if the feed was shown and the browser is in front (elapsed
  time, since a poll can block for seconds while Reels unmute) and rewrites
  `$CURRENT_FILE`. On busy → idle, or when stopped (a TERM/INT trap), it
  appends the turn to `$HISTORY_FILE` and deletes the current file. The
  per-second path uses only builtins (`$SECONDS`, `printf`), no forks.

### Stats files

`$HISTORY_FILE` has one tab-separated line per turn:
`day  start_epoch  busy_seconds  scrolled_seconds  videos  site`.
`videos` is `scrolled / site_video_seconds`, rounded, stored at record time.
`$CURRENT_FILE` is the same line for the turn that's on now. `stats_lines`
adds it to the history if it was written in the last 30 s, so a file left
by a killed watcher is ignored. The old `log` has no dates, which is why
stats have their own file. Days are local dates as of a turn's start; the
last 7 days come from `date -v-Nd`. Bars are padded by hand, because
`printf` pads by bytes and `█` is three.

## Non-obvious decisions, keep them

- **Background start goes through `perl -MPOSIX -e 'setsid; exec @ARGV'`.**
  The Claude desktop app kills the whole process group of a `!` command, so
  without a new session the watcher dies with that shell. macOS has no
  `setsid` binary.
- **The Reels pause key is the media play/pause key, not the F8 key code.**
  F8 on a Mac keyboard sends `NX_KEYTYPE_PLAY` (16), which macOS routes to
  whatever is playing. `key code 100` sends a plain F8, which the page
  ignores. `jxa/play-pause-key.js` posts the system-defined event. It checks
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
  browsers. Only the select or execute line differs per browser. Check a new
  browser case with `osacompile`: it compiles against the app's dictionary
  without sending events, so no permission prompt appears.
- **Reels sound needs a real key press first.** Chromium allows unmuted
  playback only after user activation. Clicks made from JavaScript don't
  count, and neither does `execute` from AppleScript. A System Events key
  press does count. F13 is used because it types nothing and Instagram
  ignores it. Without activation, unmuting works, but `play()` rejects with
  `NotAllowedError`. This was verified live in Arc.
- **Use Instagram's own controls, not the `<video>` element.** Clicking the
  `Audio is muted` button makes Instagram keep sound on for later reels.
  Calling `video.play()` directly gets undone, because Instagram still
  thinks the reel is paused and pauses it again. So `reels-play.js` clicks
  the `Press to play` overlay instead.
- **Arc's `execute` blocks while a page loads,** sometimes for over a minute,
  which used to freeze the watcher. `tab_js_script` wraps it in
  `with timeout of 2 seconds` and returns `"timeout"`, and callers retry.
- **Page scripts are self-contained expressions.** Every `execute` runs in
  the page's global scope, so a second top-level `const` fails and returns
  `null`. Each `page/*.js` is an IIFE whose value is the result.
  `autoscroll.js` is a bare function, and `start_autoscroll` appends the call
  with its arguments. Results come back JSON-quoted, and `run_tab_js` strips
  the quotes.
- **Autoscroll listens on `document` in the capture phase** (`ended`,
  `timeupdate`), because both feeds swap `<video>` elements as you scroll.
  Reels fire `ended` (`loop` is false). Shorts have `loop` set and never fire
  it, so a jump from the last 1.5 s back to under 1 s counts as finishing.
  A 2 s debounce keeps one finish from moving two videos.
- **YouTube labels are localized** (the user's account is Russian: "Следующее
  видео"). Select YouTube elements by id (`#navigation-button-down button`).
  Instagram's labels are English for this user, and nothing else to select by
  has been found.
- `autoscroll.js` returns `"wrong page"` while the tab still shows the
  previous page, for example right after it was pointed at the feed.
  Otherwise the script would install itself into the page that is about to
  be replaced.
- Pressing keys needs Accessibility access, and reading tabs needs Automation
  access to the browser. Both are granted to the *responsible* app, meaning
  the one the user launched doomscroller from, not doomscroller itself.

## Conventions

- Target the system `/bin/bash`, which is **3.2**: no `mapfile`, no
  associative arrays, no `${var,,}`, and `source <(…)` doesn't work. Use only
  macOS built-ins (`open`, `osascript`, `lsappinfo`, `perl`, `awk`, `jq` for
  the hook). No installs.
- Put code in the module that owns the concern, and keep calls going down
  the layers. JavaScript goes in its own file under `page/` or `jxa/`, never
  inline in bash strings.
- Each module starts with a comment saying what it owns. Each function gets
  a short comment saying what it does or why.
- Comments and user-facing text are in English.
- When you add a command, flag or setting, update `usage()` (cli.sh) and
  README.md in the same change. `usage()` is the single source for the CLI
  reference. A new setting also needs `setting_info`, `validate_setting` and
  `load_settings`. A new site needs `use_site` and `validate_setting`.
- Errors go to stderr and exit 1. Help and success output go to stdout and
  exit 0.

## Testing

There is no test suite. Exercise the code in isolation, and **never switch
windows or press keys on the real desktop** while the user is working:

- Point it at a fake status file: `DOOMSCROLLER_STATUS_FILE=/tmp/…/status.txt`.
- Use a throwaway `HOME=…` so the real `~/.doomscroller` (pid, config, log) is
  untouched. A real watcher may be running.
- Put stub `open`, `osascript` and `lsappinfo` scripts first in `PATH`. Have
  them log their arguments and return a fake frontmost app for `lsappinfo`.
  `run_tab_js` calls `osascript - <host> <url> <js>`, so a stub can answer by
  what the JS contains.
- For `init`, use a throwaway `HOME` with a writable `$HOME/bin` on `PATH`
  (and no real doomscroller on it), and pipe the answers in, one per line.
  Stub `osascript` to answer `is-trusted.js` and `count windows`. Answer "n"
  to starting, or `doomscroller stop` afterwards, since start is real.
- Rewrite the fake status file to drive transitions, then check the stub
  calls and `$HOME/.doomscroller/log`. Give a busy step about 3.5 s, because
  unmuting Reels retries for a while.
- For a refactor, diff old and new: run `git show HEAD:doomscroller` (or
  `HEAD:lib/…`) and the working copy through the same cases, and compare the
  output.
- Call single functions by sourcing modules:
  `bash -c 'LIB_DIR=lib; source lib/core.sh; source lib/browser.sh; BROWSER=Arc; tab_script'`.
- Syntax: run `bash -n` on `doomscroller` and `lib/*.sh`. For JS, run
  `osacompile` on the generated AppleScripts, and parse `page/*.js` with
  `new Function(src)` under `osascript -l JavaScript`.
- Page scripts can only really be tested live, through `run_tab_js`
  against the user's tab. Read-only probes are fine. Ask before anything
  that reloads, pauses or unmutes. The agent's shell has no Accessibility
  access, so the F13 and pause-key steps can only be tested by the user.
- **Instagram keeps reels paused while the browser window isn't focused.**
  Testing playback with Claude in front doesn't work. Test autoscroll by
  dispatching `new Event("ended")` on the visible video instead. On Shorts,
  seeking to `duration - 2` works in a background tab (`open -g -a Arc …`).

The Bash tool's shell is zsh: unquoted `$args` doesn't word-split, and
`echo ===` fails. Pass arguments explicitly in test loops.
