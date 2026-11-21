//! Mic-in-use indicator: shown only while something records from a real mic.
//!
//! Follows the PipeWire graph from one long-lived `pw-dump --monitor`; no polling.
//! Empty text hides the module. Classes: live, muted (and idle with empty text).

use crate::common::*;
use serde_json::{json, Value};
use std::collections::{BTreeSet, HashMap, HashSet};
use std::io::Read;
use std::os::unix::process::CommandExt;
use std::process::{Command, Stdio};

const PARENT_CHECK_MS: i32 = 5000;
const SETTLE_MS: i32 = 150; // PipeWire changes come in bursts: wait for the burst to end
const ICON_LIVE: &str = "\u{f130}"; // Font Awesome microphone
const ICON_MUTED: &str = "\u{f131}"; // microphone-slash

fn muted(node: &Value) -> bool {
    node["info"]["params"]["Props"].as_array().into_iter().flatten()
        .find_map(|p| p.get("mute").map(|m| m.as_bool().unwrap_or(false)))
        .unwrap_or(false)
}

fn prop<'a>(n: &'a Value, k: &str) -> Option<&'a str> {
    n["info"]["props"][k].as_str().filter(|s| !s.is_empty())
}

/// (app, mic description, mic muted) for every running capture from a mic.
fn recorders(objs: &HashMap<i64, Value>) -> BTreeSet<(String, String, bool)> {
    let nodes: HashMap<i64, &Value> = objs.iter()
        .filter(|(_, o)| o["type"] == "PipeWire:Interface:Node").map(|(k, v)| (*k, v)).collect();
    let mut feeds: HashMap<i64, HashSet<i64>> = HashMap::new();
    for o in objs.values().filter(|o| o["type"] == "PipeWire:Interface:Link") {
        if let (Some(i), Some(out)) = (o["info"]["input-node-id"].as_i64(), o["info"]["output-node-id"].as_i64()) {
            feeds.entry(i).or_default().insert(out);
        }
    }
    let mut out = BTreeSet::new();
    for (nid, n) in &nodes {
        if prop(n, "media.class") != Some("Stream/Input/Audio") || n["info"]["state"] != "running" {
            continue;
        }
        let truthy = |k: &str| match &n["info"]["props"][k] {
            Value::Bool(b) => *b,
            Value::String(s) => !s.is_empty(),
            Value::Number(x) => x.as_f64() != Some(0.0),
            _ => false,
        };
        if truthy("stream.capture.sink") || truthy("stream.monitor") {
            continue;
        }
        let app = prop(n, "application.name").or(prop(n, "application.process.binary"))
            .or(prop(n, "node.name")).unwrap_or("?");
        for src in feeds.get(nid).into_iter().flatten() {
            let Some(m) = nodes.get(src) else { continue };
            if !matches!(prop(m, "media.class"), Some("Audio/Source" | "Audio/Duplex")) {
                continue; // unlinked, or fed by a sink's monitor
            }
            let desc = prop(m, "node.description").or(prop(m, "node.name")).unwrap_or("mic");
            out.insert((app.to_string(), desc.to_string(), muted(m)));
        }
    }
    out
}

fn render(recs: &BTreeSet<(String, String, bool)>) -> Value {
    if recs.is_empty() {
        return json!({"text": "", "class": "idle", "tooltip": ""});
    }
    let all_muted = recs.iter().all(|r| r.2);
    let apps: BTreeSet<&str> = recs.iter().map(|r| r.0.as_str()).collect();
    let mut lines = vec![format!("<b>{}</b>", if all_muted { "Mic muted" } else { "Mic live" })];
    for (app, mic, m) in recs {
        lines.push(format!("{}  {}  <small>{}</small>", if *m { ICON_MUTED } else { ICON_LIVE }, escape(app), escape(mic)));
    }
    lines.push("\n<small>click: mute / unmute   right-click: recording mixer</small>".into());
    let st = if all_muted { "muted" } else { "live" };
    json!({
        "text": if all_muted { ICON_MUTED } else { ICON_LIVE },
        "class": st, "alt": st, "tooltip": lines.join("\n"), "percentage": apps.len(),
    })
}

/// An update carries the object's changed parts; keep the rest.
fn merge(old: &mut Value, new: Value) {
    match (old, new) {
        (Value::Object(o), Value::Object(n)) => {
            for (k, v) in n {
                match o.get_mut(&k) {
                    Some(slot) => merge(slot, v),
                    None => {
                        o.insert(k, v);
                    }
                }
            }
        }
        (slot, n) => *slot = n,
    }
}

/// Fold one `pw-dump --monitor` batch into {id: object}; info null removes.
fn apply(objs: &mut HashMap<i64, Value>, batch: Value) {
    let Value::Array(items) = batch else { return };
    for o in items {
        let Some(id) = o.get("id").and_then(Value::as_i64) else { continue };
        if o.get("info").is_some_and(Value::is_null) {
            objs.remove(&id);
        } else {
            match objs.get_mut(&id) {
                Some(old) => merge(old, o),
                None => {
                    objs.insert(id, o);
                }
            }
        }
    }
}

pub fn run() {
    let parent = getppid(); // waybar; reparented means it is gone
    let mut last = String::new();
    loop {
        let mut cmd = Command::new("pw-dump");
        cmd.args(["--monitor", "--no-colors"]).stdout(Stdio::piped()).stderr(Stdio::null()).stdin(Stdio::null());
        unsafe {
            cmd.pre_exec(|| {
                libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGTERM);
                Ok(())
            });
        }
        let Ok(mut child) = cmd.spawn() else {
            if getppid() != parent {
                return;
            }
            std::thread::sleep(std::time::Duration::from_secs(2));
            continue;
        };
        let mut out = child.stdout.take().unwrap();
        let fd = std::os::fd::AsRawFd::as_raw_fd(&out);
        // The first batch is the whole graph, each later one the objects that
        // changed. State is built from the stream alone: running pw-dump per
        // change would itself be a change and feed back into a busy loop.
        let (mut objs, mut buf, mut dirty) = (HashMap::new(), Vec::<u8>::new(), false);
        let mut chunk = vec![0u8; 65536];
        loop {
            let ready = poll(&[fd], if dirty { SETTLE_MS } else { PARENT_CHECK_MS })[0];
            if getppid() != parent {
                let _ = child.kill();
                return;
            }
            if ready {
                match out.read(&mut chunk) {
                    Ok(0) | Err(_) => break, // pw-dump exited (PipeWire restarted)
                    Ok(n) => buf.extend_from_slice(&chunk[..n]),
                }
                let mut consumed = 0;
                let mut it = serde_json::Deserializer::from_slice(&buf).into_iter::<Value>();
                loop {
                    match it.next() {
                        Some(Ok(batch)) => {
                            apply(&mut objs, batch);
                            consumed = it.byte_offset();
                            dirty = true;
                        }
                        Some(Err(e)) if e.is_eof() => break, // incomplete: wait for more
                        Some(Err(_)) => {
                            consumed = buf.len(); // garbage: drop it
                            break;
                        }
                        None => {
                            consumed = buf.len();
                            break;
                        }
                    }
                }
                buf.drain(..consumed);
                continue;
            }
            if !dirty {
                continue; // just the parent check's wakeup
            }
            // a burst of changes has settled: redraw if what we show changed
            let v = render(&recorders(&objs));
            let line = v.to_string();
            if line != last {
                emit(&v);
                last = line;
            }
            dirty = false;
        }
        let _ = child.kill();
        let _ = child.wait();
        std::thread::sleep(std::time::Duration::from_secs(2));
    }
}


#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn merge_and_remove() {
        let mut objs = HashMap::new();
        apply(&mut objs, json!([{"id": 1, "info": {"props": {"a": 1, "b": 2}}}]));
        apply(&mut objs, json!([{"id": 1, "info": {"props": {"b": 3}}}]));
        assert_eq!(objs[&1]["info"]["props"], json!({"a": 1, "b": 3}));
        apply(&mut objs, json!([{"id": 1, "info": null}]));
        assert!(objs.is_empty());
    }

    #[test]
    fn mic_vs_monitor() {
        let mut objs = HashMap::new();
        let node = |id: i64, class: &str, extra: Value| {
            let mut props = json!({"media.class": class, "node.description": "Mic"});
            props.as_object_mut().unwrap().extend(extra.as_object().unwrap().clone());
            json!({"id": id, "type": "PipeWire:Interface:Node", "info": {"state": "running", "props": props,
                   "params": {"Props": [{"mute": true}]}}})
        };
        apply(&mut objs, json!([node(1, "Audio/Source", json!({})),
            node(2, "Stream/Input/Audio", json!({"application.name": "rec"})),
            node(3, "Stream/Input/Audio", json!({"application.name": "cava", "stream.capture.sink": true})),
            {"id": 9, "type": "PipeWire:Interface:Link", "info": {"input-node-id": 2, "output-node-id": 1}},
            {"id": 10, "type": "PipeWire:Interface:Link", "info": {"input-node-id": 3, "output-node-id": 1}}]));
        let r = recorders(&objs);
        assert_eq!(r.into_iter().collect::<Vec<_>>(), vec![("rec".to_string(), "Mic".to_string(), true)]);
    }
}
