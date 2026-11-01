# Paths and logging shared by every module.

STATE_DIR="$HOME/.doomscroller"
PID_FILE="$STATE_DIR/pid"
LOG_FILE="$STATE_DIR/log"
CONFIG_FILE="$STATE_DIR/config"
# Scroll stats, written by the watcher (see stats.sh).
HISTORY_FILE="$STATE_DIR/history"
CURRENT_FILE="$STATE_DIR/current"

# Written by hooks/session-status.sh: one line per Claude Code session.
STATUS_FILE="${DOOMSCROLLER_STATUS_FILE:-$STATE_DIR/claude-status}"

log() { echo "$(date '+%H:%M:%S') $*"; }
