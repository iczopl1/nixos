// Reads the caption line YouTube draws over the video (captions must be on)
// and sends it to the background script whenever it changes. While a video
// plays it also sends a heartbeat every 3 s, so the bar can tell old text
// from live text. A paused or ended video sends one empty update.
(() => {
  let last = null;

  function captionText() {
    const lines = document.querySelectorAll(".ytp-caption-window-container .caption-visual-line");
    const parts = [];
    lines.forEach(l => {
      const t = Array.from(l.querySelectorAll(".ytp-caption-segment")).map(s => s.textContent).join("");
      if (t.trim()) parts.push(t.trim());
    });
    if (!parts.length) {   // other layouts: any caption segment on the page
      document.querySelectorAll(".ytp-caption-segment, .captions-text").forEach(s => {
        const t = s.textContent.trim();
        if (t && !parts.includes(t)) parts.push(t);
      });
    }
    return parts.join(" ").replace(/\s+/g, " ").trim();
  }

  function video() {
    return document.querySelector("video.html5-main-video") || document.querySelector("video");
  }

  function title() {
    return document.title.replace(/^\(\d+\)\s*/, "").replace(/ - YouTube( Music)?$/, "");
  }

  function send(force) {
    const v = video();
    const playing = !!(v && !v.paused && !v.ended);
    const text = playing ? captionText() : "";
    const key = text + "|" + playing;
    if (!force && key === last) return;
    if (!playing && last === null) return;   // never played here: stay quiet
    last = key;
    try {
      browser.runtime.sendMessage({ text, playing, title: title() }).catch(() => {});
    } catch (e) {}
  }

  // YouTube changes the page constantly: check at most every 50 ms
  let queued = false;
  new MutationObserver(() => {
    if (queued) return;
    queued = true;
    setTimeout(() => { queued = false; send(false); }, 50);
  }).observe(document.documentElement, {
    childList: true, subtree: true, characterData: true,
  });
  document.addEventListener("play", () => send(true), true);
  document.addEventListener("pause", () => send(true), true);
  document.addEventListener("ended", () => send(true), true);
  setInterval(() => {
    const v = video();
    if (v && !v.paused && !v.ended) send(true);
  }, 3000);
  window.addEventListener("pagehide", () => {
    try { browser.runtime.sendMessage({ text: "", playing: false, title: "" }).catch(() => {}); } catch (e) {}
  });
})();
