// Runs in the Reels tab. Clicks Instagram's own sound button, so Instagram
// keeps the sound on for the next reels too. Reports whether the browser saw
// user interaction (needed to play with sound) and whether the reel is muted.
(() => {
  window.__doomscroller = true;
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.top >= 0 && r.top < innerHeight; };
  const icon = [...document.querySelectorAll('svg[aria-label="Audio is muted"]')].find(visible);
  if (icon) icon.closest("[role=button]").click();
  const video = [...document.querySelectorAll("video")].find(visible);
  return "activated=" + navigator.userActivation.hasBeenActive + " muted=" + (video ? video.muted : "?");
})()
