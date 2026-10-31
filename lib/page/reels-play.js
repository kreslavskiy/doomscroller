// Runs in the Reels tab. Says "playing", or starts a paused reel and says
// "started".
//
// Clicks Instagram's own "Press to play" overlay: calling video.play()
// directly gets undone, because Instagram still thinks the reel is paused
// and pauses it again.
(() => {
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.top >= 0 && r.top < innerHeight; };
  const video = [...document.querySelectorAll("video")].find(visible);
  if (!video) return "no video";
  if (!video.paused) return "playing";
  const overlay = [...document.querySelectorAll('[role=button][aria-label="Press to play"]')].find(visible);
  if (overlay) overlay.click(); else video.play().catch(() => {});
  return "started";
})()
