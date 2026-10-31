# What differs between the feeds. To add a site, add a case here and
# teach validate_setting (settings.sh) and usage (cli.sh) about it.

# Sets SITE, URL (the feed), PAUSE_KEY (space or play, see press_pause_key)
# and NEXT_BUTTON (CSS selector autoscroll clicks) for a site.
use_site() {
  case "$1" in
    reels)  URL="https://www.instagram.com/reels/"; PAUSE_KEY=play
            NEXT_BUTTON='[aria-label="Navigate to next reel"]' ;;
    # YouTube's labels follow the account language, so go by id instead.
    shorts) URL="https://www.youtube.com/shorts";   PAUSE_KEY=space
            NEXT_BUTTON='#navigation-button-down button' ;;
    *) echo "unknown site: $1 (use reels or shorts)"; exit 1 ;;
  esac
  SITE="$1"
}
