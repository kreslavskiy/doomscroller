# doomscroller

<img width="300" height="179" alt="image" src="https://github.com/user-attachments/assets/6bea4bb8-e625-4ddb-a439-d38fd3fdf03b" />


Watch Instagram Reels or YouTube Shorts while Claude Code works, and get pulled
back the moment it needs you.

When Claude starts working, doomscroller opens the feed in your browser. When
Claude finishes or stops to ask you something, it pauses the video and brings
Claude back to the front. If you've switched to another app yourself, it
leaves you there and sends a notification instead.

macOS only. Plain bash, no dependencies beyond what ships with macOS.

## Demo

https://github.com/user-attachments/assets/cb48674b-f05c-414f-b751-8142a6e5fb0e

## How it works

```
Claude Code hooks ──▶ ~/.doomscroller/claude-status ──▶ doomscroller ──▶ browser / Claude
```

1. **Hook** ([hooks/session-status.sh](hooks/session-status.sh)). Claude Code
   runs it on its lifecycle events. It keeps one line per open session in
   `~/.doomscroller/claude-status`:
   - `busy` when you send a prompt and after every tool call;
   - `waiting` when Claude asks for permission or input;
   - `idle` when a session starts or Claude finishes its turn;
   - the line is removed when the session ends.
2. **Watcher** ([doomscroller](doomscroller), with its modules in
   [lib/](lib)). It reads that file once a
   second. Claude counts as busy if any session is busy.
   - **busy**: once Claude has been busy for 3 seconds (the `delay`
     setting) and the Claude app is in front, shows the feed in the
     browser. So a quick reply doesn't send you to the browser and right
     back, and if you switched to Slack after sending the prompt, you stay
     in Slack. Come back to Claude while it's still working and the feed
     opens then.

     It prefers a tab
     already on the feed and doesn't reload it, so you keep your place.
     Otherwise it takes any tab on the same site and points it at the feed,
     for example an Instagram profile becomes Reels. Without such a tab, it
     opens a new one.

     On Reels it also turns the sound on. A freshly loaded Instagram page
     starts muted, because the browser allows sound only after you've
     interacted with the page. So doomscroller presses F13, a key that types
     nothing but counts as interaction, then clicks Instagram's own sound
     button and starts the reel. It does this once per page load, so if you
     mute a reel yourself, it stays muted.

     With autoscroll on, it also makes the feed move by itself: when the
     video on screen finishes, it clicks the site's "next" button. Videos
     always play to the end. While Claude is idle the video is paused, so the
     feed stops too.
   - **busy → idle/waiting**: if you're in the feed, pauses the video and
     switches to the Claude app. If you're in some other app, it doesn't
     pull you out: it shows a notification, "Claude is done" or "Claude
     needs you". If you're already in Claude, it does nothing.

## Install

```bash
npm install -g @kreslavskiy/doomscroller
```

```bash
doomscroller init
```

`init` walks you through the setup and asks before changing anything:

1. Checks that `doomscroller` is on your `PATH`. When you run it from a
   clone, it links it into a folder there (`/opt/homebrew/bin`,
   `/usr/local/bin`, `~/.local/bin` or `~/bin`, whichever you can write to).
2. Copies the hook into `~/.claude/hooks` and adds it to
   `~/.claude/settings.json`, keeping your other settings. The old file is
   saved as `settings.json.bak`.
3. Asks for your feed (Reels or Shorts), browser, the app to come back to,
   and whether to autoscroll.
4. Checks the permissions below and opens the right System Settings page if
   one is missing.
5. Adds the [menu bar icon](#menu-bar) if you have SwiftBar or xbar.
6. Offers to start doomscroller.

Run it from the app you'll run `doomscroller` from, since that's the app the
permissions go to. It's safe to run again: finished steps show a ✓ and are
skipped. `init --yes` takes the default answer everywhere. After an
update (`npm update -g @kreslavskiy/doomscroller`), run `init` again to refresh the hook.

The hook needs `jq`, which macOS 15 and later include.

### From source

To change the code, clone the repo and run `init` from it. It links the
command to your clone, so your edits take effect right away:

```bash
git clone https://github.com/kreslavskiy/doomscroller.git ~/Developer/doomscroller
```

```bash
~/Developer/doomscroller/doomscroller init
```

### Uninstall

```bash
doomscroller uninstall
```

```bash
npm uninstall -g @kreslavskiy/doomscroller
```

`uninstall` stops the watcher, takes the hook out of
`~/.claude/settings.json` (keeping a `.bak`) and `~/.claude/hooks`, and
deletes `~/.doomscroller`. Do it before `npm uninstall`, which doesn't touch
any of these.

### Manual setup

What `init` does, by hand, for a clone:

1. Put `doomscroller` on your `PATH`:

   ```bash
   ln -s ~/Developer/doomscroller/doomscroller /opt/homebrew/bin/doomscroller
   ```

   Use a symlink rather than a copy: the command finds its `lib/` folder
   next to the file the link points to.

2. Install the hook. Link the script into Claude's hooks folder:

   ```bash
   mkdir -p ~/.claude/hooks && ln -s ~/Developer/doomscroller/hooks/session-status.sh ~/.claude/hooks/session-status.sh
   ```

   Then add this to `~/.claude/settings.json`, merging it with any `hooks` you
   already have:

   ```json
   {
     "hooks": {
       "SessionStart":     [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh idle" }] }],
       "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh busy" }] }],
       "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh busy" }] }],
       "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh waiting" }] }],
       "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh idle" }] }],
       "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.claude/hooks/session-status.sh end" }] }]
     }
   }
   ```

   Sessions started after this change will show up in
   `~/.doomscroller/claude-status`.

3. Choose your settings with `doomscroller config` (see
   [Configuration](#configuration)).

### Permissions

The app you run `doomscroller` from (Terminal, iTerm, Claude…) needs two
permissions, both in System Settings → Privacy & Security:

- **Accessibility**, for pressing keys (pause, and F13 before unmuting
  Reels). Without it, videos aren't paused and Reels stay muted.
- **Automation → your browser**, for finding the open tab and turning on
  Reels sound. macOS asks the first time. Without it, the page opens once,
  later turns only bring the browser forward, and Reels stay muted.

The log tells you when something is missing.

Tab reuse works in Arc, Safari, Google Chrome, Brave, Edge, Chromium and
Vivaldi. Other browsers fall back to opening the page once. Turning on
Reels sound runs JavaScript in the tab. Arc allows that as is. Chrome-like
browsers need View → Developer → Allow JavaScript from Apple Events, and
Safari needs Develop → Allow JavaScript from Apple Events.

## Usage

```bash
doomscroller init               # set up, or change your answers later
doomscroller start              # Reels (or your configured site), in the background
doomscroller start --shorts     # YouTube Shorts this time
doomscroller start --autoscroll # go to the next video when one ends
doomscroller start -w           # stay in the terminal and log Claude's state every second
doomscroller status             # running? what is Claude doing?
doomscroller stats              # how long you scrolled while Claude worked
doomscroller stop
doomscroller menubar            # add the menu bar icon
doomscroller --help
doomscroller --version
```

`start` also takes a URL to open instead of the feed. It gets paused the same
way as the chosen site.

The background watcher logs every switch to `~/.doomscroller/log`. In watch
mode (`-w`) it prints to the terminal instead, including every poll:

```
14:26:47 watching, Claude is idle
14:26:48 busy | idle my-project, busy doomscroller
14:26:48 busy
14:26:49 busy | idle my-project, busy doomscroller
14:26:50 busy | idle my-project, busy doomscroller
14:26:51 busy | idle my-project, busy doomscroller
14:26:51 busy -> Arc
14:27:30 idle | idle my-project, idle doomscroller
14:27:30 idle -> Claude
14:27:30 paused video (play key)
```

## Stats

`doomscroller stats` shows how long Claude worked and how much of that you
spent in the feed:

```
Today
  Claude worked  1h 42m in 23 turns
  You scrolled   1h 18m, ≈ 187 videos (76% of Claude's time)

Last 7 days
  Mon 26  ████████████████████  2h 10m
  Tue 27  ██████████████        1h 31m
  Wed 28  ████████              52m
  Thu 29                        -
  Fri 30  █████████████████     1h 51m
  Sat 31  ███                   18m
  Sun 01  ████████████          1h 18m
  8h 00m scrolled, ≈ 1150 videos, while Claude worked 11h 25m

All time: 23h 15m scrolled, ≈ 3340 videos, since Fri 23
Best day: Mon 26, 2h 10m
```

Scrolled time counts only the seconds the browser was in front, with the
feed open, while Claude was busy. The number of videos is an estimate from that time (about 25 s
per reel, 30 s per short). `doomscroller stats --share` prints a line to
post:

```
Claude worked 1h 42m for me today, and I doomscrolled 1h 18m of it (≈ 187 videos) 🍿 https://github.com/kreslavskiy/doomscroller
```

Stats start with the first turn doomscroller watches and stay in
`~/.doomscroller/history`.

## Menu bar

With [SwiftBar](https://github.com/swiftbar/SwiftBar) or
[xbar](https://xbarapp.com) installed, doomscroller can sit in the menu bar:

```bash
brew install --cask swiftbar
```

```bash
doomscroller menubar
```

Open SwiftBar once before that, so it asks for its plugin folder. The icon
shows what's going on:

| Icon (SwiftBar) | xbar | Meaning                     |
|-----------------|------|-----------------------------|
| ▶ filled        | 🍿   | Claude is working: scroll   |
| ✋              | ✋   | Claude is waiting for you   |
| ▶ outline       | 💤   | Claude is idle              |
| ▶ crossed out   | ⏹    | doomscroller is off         |

Next to the icon is how long you've scrolled today, ticking up while you
scroll.

The menu lists your Claude sessions and their states, and today's
[stats](#stats): time scrolled, the estimated videos, the share of
Claude's time, the last 7 days and your best day (or a 🏆 when today is
the new record). "Copy for sharing" puts the `stats --share` line on the
clipboard, and "Show all stats" opens the full `stats` in Terminal. The
menu also turns doomscroller on and off, switches between Reels and
Shorts, toggles autoscroll and opens the log. Changing the feed or autoscroll there saves it to the config and
restarts a running doomscroller, so it applies at once.

When you turn doomscroller on from the menu, it runs under SwiftBar (or
xbar), so that app needs the Accessibility and Automation access described
under [Permissions](#permissions). `doomscroller menubar uninstall` removes
the icon.

## Configuration

```bash
doomscroller config                          # show all settings and where each comes from
doomscroller config set site shorts
doomscroller config set browser Google Chrome
doomscroller config set claude-app iTerm
doomscroller config set autoscroll on
doomscroller config get browser
doomscroller config unset browser            # back to the default
```

| Setting      | Values                           | Default  |
|--------------|----------------------------------|----------|
| `site`       | `reels`, `shorts`                | `reels`  |
| `browser`    | any app in `/Applications` etc.  | `Arc`    |
| `claude-app` | the app to return to             | `Claude` |
| `autoscroll` | `on`, `off`                      | `off`    |
| `delay`      | seconds busy before the feed opens | `3`    |

Settings live in `~/.doomscroller/config`. For a one-off run, the environment
variables `DOOMSCROLLER_SITE`, `DOOMSCROLLER_BROWSER`,
`DOOMSCROLLER_CLAUDE_APP`, `DOOMSCROLLER_AUTOSCROLL` and `DOOMSCROLLER_DELAY`
override the config.
Flags for `start` beat both: `--reels`/`--shorts` override `site`, and
`--autoscroll`/`--no-autoscroll` override `autoscroll`. A running watcher
picks up changes only after a restart.

How each site gets paused:

| Site     | Page                               | Pause key                               | Autoscroll clicks              |
|----------|------------------------------------|-----------------------------------------|--------------------------------|
| `reels`  | `https://www.instagram.com/reels/` | media play/pause (F8 on a Mac keyboard) | "Navigate to next reel"        |
| `shorts` | `https://www.youtube.com/shorts`   | space                                   | the down arrow next to a Short |

Autoscroll runs JavaScript in the tab, like Reels sound, so it needs the same
browser setup.

## Security

doomscroller makes no network requests of its own. In the browser it only
touches the feed's tab: the video player and its buttons. Its config is
parsed, never executed. But the permissions it needs are broad, so know what you're
granting:

- **Accessibility and Automation go to the whole app you run it from,** not
  to doomscroller. If that's Terminal, any script you run in Terminal can
  then press keys and control your browser without asking again. To limit
  this, run doomscroller from a terminal app you don't use for anything
  else, and remove the permissions when you stop using it.
- **"Allow JavaScript from Apple Events"** (needed in Chrome-like browsers
  and Safari for Reels sound and autoscroll) lets any app with Automation
  access to the browser run JavaScript in every tab, including tabs where
  you're logged in. Arc allows this without a setting. Leave the option off
  if you don't need those two features. Tab switching and pausing work
  without it.
- The hook and the watcher write only to `~/.doomscroller/`.

## Caveats

- **Pausing toggles.** Both keys toggle playback, so a video you had already
  paused will start playing again.
- **Space goes to the page.** On Shorts, if a text field such as the search
  box has focus, the space is typed into it instead.
- **Stale busy lines.** If a session crashes without its `SessionEnd` hook, its
  `busy` line stays in the status file and doomscroller thinks Claude is still
  working. Delete that line from `~/.doomscroller/claude-status`.
- **Reels sound and autoscroll depend on the sites' pages.** They find
  buttons by their labels (`Audio is muted`, `Press to play`,
  `Navigate to next reel`) or by YouTube's element id, so a redesign can
  break them. If the "next" button is gone, autoscroll falls back to
  scrolling the feed by a screen.
- **Seeking back counts as finishing.** On Shorts, a video that jumps from
  its last second back to the start counts as finished, because that's how
  Shorts loop. Rewinding to the start during the last second does the same.
- **The feed takes over the site's tab.** Every turn sends the Instagram (or
  YouTube) tab back to the feed, even if you were reading DMs there.
- **Notifications come from Script Editor.** They're shown with
  `osascript`, so macOS lists them under Script Editor, and clicking one
  opens it.
- **"In Claude" means the app.** If Claude Code runs in a terminal, any
  window of that terminal counts, not just the one with Claude.

## Files

| Path                            | What                                |
|---------------------------------|-------------------------------------|
| `~/.doomscroller/claude-status` | session states, written by the hook |
| `~/.doomscroller/config`        | settings (`key=value` lines)        |
| `~/.doomscroller/log`           | background watcher log              |
| `~/.doomscroller/pid`           | pid of the running watcher          |
| `~/.doomscroller/history`       | stats: one line per Claude turn     |
| `~/.doomscroller/current`       | stats for the turn that's on now    |

## License

[MIT](LICENSE)
