# Scroll stats: how long Claude worked, and how long the browser was in front
# meanwhile. The watcher adds one tab-separated line per busy turn to
# $HISTORY_FILE:
#   day  start  busy_seconds  scrolled_seconds  videos  site
# "videos" is an estimate from the site's typical time per video. While a
# turn is on, its numbers so far are in $CURRENT_FILE, so stats include it.

# Prints a turn's stats line. Called every second, so it uses only builtins.
# Usage: stats_line <day> <start epoch> <busy seconds> <scrolled seconds>
stats_line() {
  local per_video
  per_video=$(site_video_seconds "$SITE")
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" \
    $((($4 + per_video / 2) / per_video)) "$SITE"
}

# Saves the turn so far. Usage: same as stats_line.
stats_update() {
  stats_line "$@" > "$CURRENT_FILE"
}

# Adds a finished turn to the history. Usage: same as stats_line.
stats_record() {
  stats_line "$@" >> "$HISTORY_FILE"
  rm -f "$CURRENT_FILE"
}

# Prints the history, plus the turn that's on now. A current file that hasn't
# been touched for a while is left over from a watcher that died, so it's skipped.
stats_lines() {
  [ -f "$HISTORY_FILE" ] && cat "$HISTORY_FILE"
  if [ -f "$CURRENT_FILE" ] && [ $(($(date +%s) - $(stat -f %m "$CURRENT_FILE"))) -lt 30 ]; then
    cat "$CURRENT_FILE"
  fi
}

# Prints "turns busy scrolled videos" summed over the given days (YYYY-MM-DD),
# or over everything if none are given. Usage: stats_sum [day]...
stats_sum() {
  stats_lines | awk -F'\t' -v days=" $* " '
    days == "  " || index(days, " " $1 " ") { n++; busy += $3; scrolled += $4; videos += $5 }
    END { print n + 0, busy + 0, scrolled + 0, videos + 0 }'
}

# Prints the day with the most scrolling and its seconds, e.g. "2026-10-28 7800".
stats_best_day() {
  stats_lines | awk -F'\t' '
    { scrolled[$1] += $4 }
    END { for (day in scrolled) if (scrolled[day] > best) { best = scrolled[day]; top = day }
          if (top != "") print top, best }'
}

# Prints the first day with stats.
stats_first_day() {
  stats_lines | head -1 | cut -f1
}

# Prints the last n days, oldest first, as YYYY-MM-DD. Usage: last_days <n>
last_days() {
  local i
  for ((i = $1 - 1; i >= 0; i--)); do
    date -v-${i}d +%F
  done
}

# Prints seconds as "1h 05m", "12m" or "40s".
fmt_duration() {
  local s="$1"
  if [ "$s" -ge 3600 ]; then printf '%dh %02dm' $((s / 3600)) $((s % 3600 / 60))
  elif [ "$s" -ge 60 ]; then printf '%dm' $((s / 60))
  else printf '%ds' "$s"
  fi
}

# Prints a day as "Tue 28". Usage: fmt_day <YYYY-MM-DD>
fmt_day() {
  date -j -f %F "$1" '+%a %d'
}

# Prints a bar of up to 20 blocks for value out of max, padded to 20
# columns (by hand: printf pads by bytes, and █ is three). Usage: bar <value> <max>
bar() {
  local blocks=0 i out=""
  [ "$2" -gt 0 ] && blocks=$((($1 * 20 + $2 / 2) / $2))
  [ "$1" -gt 0 ] && [ "$blocks" -eq 0 ] && blocks=1
  for ((i = 0; i < 20; i++)); do
    if [ "$i" -lt "$blocks" ]; then out="$out█"; else out="$out "; fi
  done
  printf '%s' "$out"
}

# Prints what part of Claude's time you scrolled, e.g. "76%". Usage: percent <scrolled> <busy>
percent() {
  [ "$2" -gt 0 ] && echo "$(($1 * 100 / $2))%" || echo "0%"
}

# doomscroller stats: today, the last 7 days with a bar per day, all time.
print_stats() {
  local turns busy scrolled videos day line max=0 per_day="" best best_day
  if [ -z "$(stats_lines)" ]; then
    echo "No stats yet. Start doomscroller and give Claude something to do."
    return
  fi

  read -r turns busy scrolled videos <<< "$(stats_sum "$(date +%F)")"
  echo "Today"
  printf '  Claude worked  %s in %d turns\n' "$(fmt_duration "$busy")" "$turns"
  printf '  You scrolled   %s, ≈ %d videos (%s of Claude'"'"'s time)\n' \
    "$(fmt_duration "$scrolled")" "$videos" "$(percent "$scrolled" "$busy")"

  echo
  echo "Last 7 days"
  for day in $(last_days 7); do
    read -r turns busy scrolled videos <<< "$(stats_sum "$day")"
    per_day="$per_day $day:$scrolled"
    [ "$scrolled" -gt "$max" ] && max=$scrolled
  done
  for day in $per_day; do
    scrolled=${day#*:}
    if [ "$scrolled" -gt 0 ]; then line=$(fmt_duration "$scrolled"); else line="-"; fi
    printf '  %s  %s  %s\n' "$(fmt_day "${day%:*}")" "$(bar "$scrolled" "$max")" "$line"
  done
  read -r turns busy scrolled videos <<< "$(stats_sum $(last_days 7))"
  printf '  %s scrolled, ≈ %d videos, while Claude worked %s\n' \
    "$(fmt_duration "$scrolled")" "$videos" "$(fmt_duration "$busy")"

  echo
  read -r turns busy scrolled videos <<< "$(stats_sum)"
  read -r best_day best <<< "$(stats_best_day)"
  printf 'All time: %s scrolled, ≈ %d videos, since %s\n' \
    "$(fmt_duration "$scrolled")" "$videos" "$(fmt_day "$(stats_first_day)")"
  [ -n "$best_day" ] && printf 'Best day: %s, %s\n' "$(fmt_day "$best_day")" "$(fmt_duration "$best")"
}

# Prints a line to share: today's numbers, or the last 7 days' if today has none.
share_line() {
  local turns busy scrolled videos when="today"
  read -r turns busy scrolled videos <<< "$(stats_sum "$(date +%F)")"
  if [ "$scrolled" -eq 0 ]; then
    read -r turns busy scrolled videos <<< "$(stats_sum $(last_days 7))"
    when="this week"
  fi
  if [ "$scrolled" -eq 0 ]; then
    echo "No stats yet."
    return 1
  fi
  echo "Claude worked $(fmt_duration "$busy") for me $when, and I doomscrolled $(fmt_duration "$scrolled") of it (≈ $videos videos) 🍿 https://github.com/kreslavskiy/doomscroller"
}
