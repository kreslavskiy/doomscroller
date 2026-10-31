#!/bin/bash
# Keeps ~/Desktop/claude-status.txt: one line per open Claude Code session.
# Usage: session-status.sh <busy|waiting|idle|end>, hook JSON on stdin.

state="$1"
status_file="$HOME/Desktop/claude-status.txt"
lock_dir="$status_file.lock"

input=$(cat)
session_id=$(printf '%s' "$input" | jq -r '.session_id // empty')
cwd=$(printf '%s' "$input" | jq -r '.cwd // empty')
[ -z "$session_id" ] && exit 0

# mkdir is atomic: a lock shared by parallel sessions (macOS has no flock).
for _ in $(seq 1 50); do
  mkdir "$lock_dir" 2>/dev/null && break
  sleep 0.02
done
trap 'rmdir "$lock_dir" 2>/dev/null' EXIT

tmp_file=$(mktemp "$status_file.XXXXXX")
[ -f "$status_file" ] && grep -v -F "$session_id" "$status_file" > "$tmp_file"
if [ "$state" != "end" ]; then
  printf '%s\t%s\t%s\t%s\n' "$state" "$(date '+%Y-%m-%d %H:%M:%S')" "$session_id" "$cwd" >> "$tmp_file"
fi
mv "$tmp_file" "$status_file"
exit 0
