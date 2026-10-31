// Runs in the Reels tab. Says "loading" until a reel is on screen, then
// "muted" if the reel needs its sound turned on, otherwise "skip".
//
// A freshly loaded Instagram page starts muted. The window.__doomscroller mark
// limits unmuting to once per page load, so a reel you mute yourself stays muted.
(() => {
  if (window.__doomscroller) return "skip";
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.top >= 0 && r.top < innerHeight; };
  if (![...document.querySelectorAll("video")].some(visible)) return "loading";
  const icon = [...document.querySelectorAll('svg[aria-label="Audio is muted"]')].some(visible);
  if (!icon) window.__doomscroller = true;
  return icon ? "muted" : "skip";
})()
