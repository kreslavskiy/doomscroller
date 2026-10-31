# Paths and logging shared by every module.

# Written by hooks/session-status.sh: one line per Claude Code session.
STATUS_FILE="${DOOMSCROLLER_STATUS_FILE:-$HOME/Desktop/claude-status.txt}"

STATE_DIR="$HOME/.doomscroller"
PID_FILE="$STATE_DIR/pid"
LOG_FILE="$STATE_DIR/log"
CONFIG_FILE="$STATE_DIR/config"

log() { echo "$(date '+%H:%M:%S') $*"; }
