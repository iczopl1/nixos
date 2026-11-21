//! Clicks through the wlr virtual-pointer protocol (what wl-kbptr used, without ydotool).
//! One Wayland connection for the life of the daemon; one pointer per monitor, made on first use.
use std::collections::HashMap;
use std::time::{SystemTime, UNIX_EPOCH};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_output, wl_registry, wl_seat};
use wayland_client::{Connection, Dispatch, EventQueue, QueueHandle};
use wayland_protocols_wlr::virtual_pointer::v1::client::{
    zwlr_virtual_pointer_manager_v1::ZwlrVirtualPointerManagerV1, zwlr_virtual_pointer_v1::ZwlrVirtualPointerV1,
};

const BTN_LEFT: u32 = 0x110;
const BTN_RIGHT: u32 = 0x111;
const BTN_MIDDLE: u32 = 0x112;
const DRAG_SLOP: u32 = 14; // past the toolkit drag threshold (GTK: 8 px), so the drag starts now

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

pub struct Clicker {
    conn: Connection,
    queue: EventQueue<State>,
    state: State,
    manager: ZwlrVirtualPointerManagerV1,
    seat: wl_seat::WlSeat,
    outputs: Vec<(u32, wl_output::WlOutput)>,
    pointers: HashMap<String, ZwlrVirtualPointerV1>,
    held: Option<(String, i32, i32, i32, i32)>, // monitor, x, y, extent w, h of the pressed spot
}

fn now_ms() -> u32 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_millis() as u32).unwrap_or(0)
}

impl Clicker {
    pub fn connect() -> Result<Clicker, String> {
        let conn = Connection::connect_to_env().map_err(|e| e.to_string())?;
        let (globals, mut queue) = registry_queue_init::<State>(&conn).map_err(|e| e.to_string())?;
        let qh = queue.handle();
        let manager: ZwlrVirtualPointerManagerV1 = globals.bind(&qh, 1..=2, ()).map_err(|e| format!("virtual pointer: {e}"))?;
        let seat: wl_seat::WlSeat = globals.bind(&qh, 1..=1, ()).map_err(|e| e.to_string())?;
        let mut outputs = vec![];
        for g in globals.contents().clone_list() {
            if g.interface == "wl_output" {
                let v = g.version.min(4);
                let o = globals.registry().bind::<wl_output::WlOutput, _, _>(g.name, v, &qh, g.name);
                outputs.push((g.name, o));
            }
        }
        let mut state = State::default();
        queue.roundtrip(&mut state).map_err(|e| e.to_string())?;
        Ok(Clicker { conn, queue, state, manager, seat, outputs, pointers: HashMap::new(), held: None })
    }

    fn pointer(&mut self, monitor: &str) -> Option<ZwlrVirtualPointerV1> {
        if let Some(p) = self.pointers.get(monitor) {
            return Some(p.clone());
        }
        let qh = self.queue.handle();
        let out = self.outputs.iter().find(|(id, _)| self.state.names.get(id).map(|n| n == monitor).unwrap_or(false))?;
        let p = self.manager.create_virtual_pointer_with_output(Some(&self.seat), Some(&out.1), &qh, ());
        self.pointers.insert(monitor.to_string(), p.clone());
        Some(p)
    }

    fn at(p: &ZwlrVirtualPointerV1, x: i32, y: i32, w: i32, h: i32) {
        p.motion_absolute(now_ms(), x.max(0) as u32, y.max(0) as u32, w.max(1) as u32, h.max(1) as u32);
        p.frame();
    }

    fn button(p: &ZwlrVirtualPointerV1, code: u32, down: bool) {
        use wayland_client::protocol::wl_pointer::ButtonState;
        p.button(now_ms(), code, if down { ButtonState::Pressed } else { ButtonState::Released });
        p.frame();
    }

    /// `kind`: n = move only, l m r = click, x = double click, h = press and hold, d = drop (release) at x,y. Monitor-local logical pixels.
    pub fn click(&mut self, monitor: &str, x: i32, y: i32, w: i32, h: i32, kind: char) -> Result<(), String> {
        // Drain whatever the compositor sent since the last click (monitors coming and going).
        self.queue.roundtrip(&mut self.state).map_err(|e| e.to_string())?;
        // A drop releases on the pointer that pressed, even if the target is on another monitor.
        let press_mon = self.held.as_ref().map(|h| h.0.clone());
        let p = self.pointer(press_mon.as_deref().unwrap_or(monitor)).ok_or_else(|| format!("no output named {monitor}"))?;
        if self.held.is_some() || kind == 'd' {
            // Dropping: wiggle so the app sees motion over the target, then release.
            // A toolkit drag needs a few frames between the moves to answer "can I drop here?" before the release.
            let pause = |c: &Connection, ms: u64| { let _ = c.flush(); std::thread::sleep(std::time::Duration::from_millis(ms)); };
            Self::at(&p, x, y, w, h);
            pause(&self.conn, 80);
            Self::at(&p, x + 1, y, w, h);
            pause(&self.conn, 50);
            Self::at(&p, x, y, w, h);
            pause(&self.conn, 80);
            Self::button(&p, BTN_LEFT, false);
            self.held = None;
        } else {
            Self::at(&p, x, y, w, h);
            // Apps ignore a press that arrives with the pointer-enter: send the move, wait a beat.
            let _ = self.conn.flush();
            std::thread::sleep(std::time::Duration::from_millis(15));
            match kind {
                'l' | 'm' | 'r' => {
                    let code = match kind { 'l' => BTN_LEFT, 'm' => BTN_MIDDLE, _ => BTN_RIGHT };
                    Self::button(&p, code, true);
                    Self::button(&p, code, false);
                }
                'h' => {
                    Self::button(&p, BTN_LEFT, true);
                    // Move in steps so the toolkit sees the drag start, then the compositor takes over the pointer.
                    for step in 1..=3 {
                        let _ = self.conn.flush();
                        std::thread::sleep(std::time::Duration::from_millis(20));
                        let d = (DRAG_SLOP as i32 * step) / 3;
                        Self::at(&p, x + d, y + d, w, h);
                    }
                    self.held = Some((monitor.to_string(), x, y, w, h));
                }
                'x' => {
                    Self::button(&p, BTN_LEFT, true);
                    Self::button(&p, BTN_LEFT, false);
                    let _ = self.conn.flush();
                    std::thread::sleep(std::time::Duration::from_millis(30));
                    Self::button(&p, BTN_LEFT, true);
                    Self::button(&p, BTN_LEFT, false);
                }
                'n' => {}
                _ => return Err(format!("unknown click kind {kind}")),
            }
        }
        self.conn.flush().map_err(|e| e.to_string())
    }

    /// Esc while holding: let go where we are.
    pub fn release(&mut self) -> Result<(), String> {
        if let Some((mon, x, y, w, h)) = self.held.take() {
            if let Some(p) = self.pointer(&mon) {
                Self::at(&p, x, y, w, h);
                Self::button(&p, BTN_LEFT, false);
            }
        }
        self.conn.flush().map_err(|e| e.to_string())
    }

    pub fn holding(&self) -> bool {
        self.held.is_some()
    }
}
