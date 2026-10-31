// Runs in the feed's tab. Installs autoscroll: when the video on screen
// finishes, clicks the site's "next" button, or scrolls the feed by a screen
// if there's none.
//
// This file is a function. start_autoscroll appends the arguments, the feed
// URL and the button's CSS selector: …)("https://…", "selector"). It says
// "on", "already on" (once per page load, kept by a mark) or "wrong page"
// (an old page is still there while the browser navigates to the feed).
//
// It listens on the document in the capture phase, so it keeps working while
// the feed swaps <video> elements. A video counts as finished when it fires
// "ended" (Reels) or when it jumps from its end back to the start: Shorts loop
// on their own and never fire "ended". Paused videos never finish, so it
// stops by itself while Claude is idle.
((feedUrl, nextButton) => {
  if (!location.href.startsWith(feedUrl)) return "wrong page";
  if (window.__doomscrollerScroll) return "already on";
  window.__doomscrollerScroll = true;
  const visible = e => { const r = e.getBoundingClientRect(); return r.width > 0 && r.top >= 0 && r.top < innerHeight; };
  const scroller = e => {
    while (e && !(e.scrollHeight > e.clientHeight && /auto|scroll/.test(getComputedStyle(e).overflowY))) e = e.parentElement;
    return e || document.scrollingElement;
  };
  let lastStep = 0;
  const next = video => {
    // Only the video on screen counts, once: ended and the loop can both fire.
    if (!visible(video) || performance.now() - lastStep < 2000) return;
    lastStep = performance.now();
    const buttons = [...document.querySelectorAll(nextButton)];
    const button = buttons.find(visible) || buttons[0];
    if (button) (button.closest("button, [role=button]") || button).click();
    else scroller(video).scrollBy({ top: innerHeight, behavior: "smooth" });
  };
  const lastTime = new WeakMap();
  document.addEventListener("ended", e => next(e.target), true);
  document.addEventListener("timeupdate", e => {
    const video = e.target, before = lastTime.get(video) || 0;
    lastTime.set(video, video.currentTime);
    if (before > video.duration - 1.5 && video.currentTime < 1) next(video);
  }, true);
  return "on";
})
