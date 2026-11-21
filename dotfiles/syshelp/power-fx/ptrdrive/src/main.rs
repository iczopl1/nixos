//! ptrdrive: moves the pointer through the wlr virtual-pointer protocol.
//! Reads lines on stdin, one per move:  "<monitor> <x> <y> <width> <height>"
//! (x, y monitor-local pixels inside width x height). EOF ends it.
//! Used by the `mousedance` effect in ~/.config/quickshell/bar/Fx.qml.
use std::collections::HashMap;
use std::io::BufRead;
use std::time::{SystemTime, UNIX_EPOCH};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_output, wl_registry, wl_seat};
use wayland_client::{Connection, Dispatch, Proxy, QueueHandle};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

#[derive(Default)]
struct State {
    names: HashMap<u32, String>, // wl_output global name -> output name
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for State {
    fn event(_: &mut Self, _: &wl_registry::WlRegistry, _: wl_registry::Event, _: &GlobalListContents, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<wl_output::WlOutput, u32> for State {
    fn event(s: &mut Self, _: &wl_output::WlOutput, e: wl_output::Event, id: &u32, _: &Connection, _: &QueueHandle<Self>) {
        if let wl_output::Event::Name { name } = e {
            s.names.insert(*id, name);
        }
    }
}
impl Dispatch<wl_seat::WlSeat, ()> for State {
    fn event(_: &mut Self, _: &wl_seat::WlSeat, _: wl_seat::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwlrVirtualPointerManagerV1, ()> for State {
    fn event(_: &mut Self, _: &ZwlrVirtualPointerManagerV1, _: <ZwlrVirtualPointerManagerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwlrVirtualPointerV1, ()> for State {
    fn event(_: &mut Self, _: &ZwlrVirtualPointerV1, _: <ZwlrVirtualPointerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

fn now_ms() -> u32 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u32).unwrap_or(0)
}

fn main() {
    let conn = Connection::connect_to_env().expect("wayland connect");
    let (globals, mut queue) = registry_queue_init::<State>(&conn).expect("registry");
    let qh = queue.handle();
    let manager: ZwlrVirtualPointerManagerV1 = globals.bind(&qh, 1..=2, ()).expect("no wlr virtual pointer");
    let seat: wl_seat::WlSeat = globals.bind(&qh, 1..=1, ()).expect("no seat");
    let mut outputs = vec![];
    for g in globals.contents().clone_list() {
        if g.interface == "wl_output" {
            let o = globals.registry().bind::<wl_output::WlOutput, _, _>(g.name, g.version.min(4), &qh, g.name);
            outputs.push((g.name, o));
        }
    }
    let mut state = State::default();
    queue.roundtrip(&mut state).expect("roundtrip");

    // One pointer per monitor (version 2 maps absolute motion to that output), made on first use.
    let mut pointers: HashMap<String, ZwlrVirtualPointerV1> = HashMap::new();
    for line in std::io::stdin().lock().lines() {
        let Ok(line) = line else { break };
        let p: Vec<&str> = line.split_whitespace().collect();
        let [mon, x, y, w, h] = p.as_slice() else { continue };
        let num = |s: &str| s.parse::<f64>().ok().filter(|v| v.is_finite() && *v >= 0.0 && *v <= 100_000.0);
        let (Some(x), Some(y), Some(w), Some(h)) = (num(x), num(y), num(w), num(h)) else { continue };
        if !pointers.contains_key(*mon) {
            let out = outputs.iter().find(|(id, _)| state.names.get(id).map(|n| n == mon).unwrap_or(false));
            let Some((_, o)) = out else { continue };
            let vp = if manager.version() >= 2 {
                manager.create_virtual_pointer_with_output(Some(&seat), Some(o), &qh, ())
            } else {
                manager.create_virtual_pointer(Some(&seat), &qh, ())
            };
            pointers.insert(mon.to_string(), vp);
        }
        let vp = &pointers[*mon];
        let (w, h) = (w.max(1.0) as u32, h.max(1.0) as u32);
        vp.motion_absolute(now_ms(), (x as u32).min(w - 1), (y as u32).min(h - 1), w, h);
        vp.frame();
        if conn.flush().is_err() {
            break;
        }
    }
    for vp in pointers.values() {
        vp.destroy();
    }
    let _ = conn.flush();
}
