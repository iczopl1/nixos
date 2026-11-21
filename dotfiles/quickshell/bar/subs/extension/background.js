// Forwards caption updates from YouTube tabs to the bar's music script
// (bar/scripts/lyrics.py), which listens on 127.0.0.1:47613.
const URL = "http://127.0.0.1:47613/subs";
let warned = false;

browser.runtime.onMessage.addListener(msg => {
  fetch(URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-Bar-Subs": "1" },
    body: JSON.stringify({ text: msg.text, playing: msg.playing, title: msg.title }),
  }).then(() => {
    if (warned) console.log("bar-subs: bar reachable again");
    warned = false;
  }).catch(e => {
    if (!warned) console.error("bar-subs: bar not reachable:", e.message);
    warned = true;
  });
});
console.log("bar-subs: background loaded");
