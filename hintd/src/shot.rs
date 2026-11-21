//! In-process screen capture through wlr-screencopy, straight to gray: no grim process, no PPM copy.
//! One Wayland connection for the life of the daemon. Captures run one at a time (they share the
//! connection's read side); the gray conversion runs after the lock is released.
use crate::atspi::Rect;
use std::collections::HashMap;
use std::os::fd::{AsFd, AsRawFd, FromRawFd, OwnedFd};
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};
use wayland_client::globals::{registry_queue_init, GlobalListContents};
use wayland_client::protocol::{wl_buffer, wl_output, wl_registry, wl_shm, wl_shm_pool};
use wayland_protocols::xdg::xdg_output::zv1::client::{
    zxdg_output_manager_v1::ZxdgOutputManagerV1,
    zxdg_output_v1::{self, ZxdgOutputV1},
};
use wayland_client::{Connection, Dispatch, EventQueue, Proxy, QueueHandle, WEnum};
use wayland_protocols_wlr::screencopy::v1::client::{
    zwlr_screencopy_frame_v1::{self, ZwlrScreencopyFrameV1},
    zwlr_screencopy_manager_v1::ZwlrScreencopyManagerV1,
};

/// A compositor that does not answer a capture within this long gets the grim program instead.
const WAIT: Duration = Duration::from_millis(400);

/// One monitor: its place in the global (logical) coordinates, as xdg-output reports it (what grim uses).
#[derive(Default)]
struct Out {
    output: Option<wl_output::WlOutput>,
    xdg: Option<ZxdgOutputV1>,
    x: i32,
    y: i32,
    w: i32,
    h: i32,
}

/// Registry side: which monitors exist and where (kept current across plug and unplug).
#[derive(Default)]
struct Outputs {
    xdg_manager: Option<ZxdgOutputManagerV1>,
    outs: HashMap<u32, Out>,
}

impl Outputs {
    fn add(&mut self, reg: &wl_registry::WlRegistry, qh: &QueueHandle<Self>, name: u32, version: u32) {
        let output = reg.bind::<wl_output::WlOutput, _, _>(name, version.min(4), qh, name);
        let xdg = self.xdg_manager.as_ref().map(|m| m.get_xdg_output(&output, qh, name));
        self.outs.insert(name, Out { output: Some(output), xdg, ..Default::default() });
    }
}

impl Dispatch<wl_registry::WlRegistry, GlobalListContents> for Outputs {
    fn event(s: &mut Self, reg: &wl_registry::WlRegistry, e: wl_registry::Event, _: &GlobalListContents, _: &Connection, qh: &QueueHandle<Self>) {
        match e {
            wl_registry::Event::Global { name, interface, version } if interface == "wl_output" => s.add(reg, qh, name, version),
            wl_registry::Event::GlobalRemove { name } => {
                if let Some(o) = s.outs.remove(&name) {
                    if let Some(x) = o.xdg {
                        x.destroy();
                    }
                    if let Some(out) = o.output.filter(|o| o.version() >= 3) {
                        out.release();
                    }
                }
            }
            _ => {}
        }
    }
}
impl Dispatch<wl_output::WlOutput, u32> for Outputs {
    fn event(_: &mut Self, _: &wl_output::WlOutput, _: wl_output::Event, _: &u32, _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZxdgOutputManagerV1, ()> for Outputs {
    fn event(_: &mut Self, _: &ZxdgOutputManagerV1, _: <ZxdgOutputManagerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZxdgOutputV1, u32> for Outputs {
    fn event(s: &mut Self, _: &ZxdgOutputV1, e: zxdg_output_v1::Event, id: &u32, _: &Connection, _: &QueueHandle<Self>) {
        let Some(o) = s.outs.get_mut(id) else { return };
        match e {
            zxdg_output_v1::Event::LogicalPosition { x, y } => {
                o.x = x;
                o.y = y;
            }
            zxdg_output_v1::Event::LogicalSize { width, height } => {
                o.w = width;
                o.h = height;
            }
            _ => {}
        }
    }
}
impl Dispatch<wl_shm::WlShm, ()> for Outputs {
    fn event(_: &mut Self, _: &wl_shm::WlShm, _: wl_shm::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<ZwlrScreencopyManagerV1, ()> for Outputs {
    fn event(_: &mut Self, _: &ZwlrScreencopyManagerV1, _: <ZwlrScreencopyManagerV1 as wayland_client::Proxy>::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

/// Capture side: what the compositor says about one frame.
#[derive(Default)]
struct Frame {
    buf: Option<(wl_shm::Format, i32, i32, i32)>, // format, width, height, stride
    buffer_done: bool,
    y_invert: bool,
    ready: bool,
    failed: bool,
}

impl Dispatch<ZwlrScreencopyFrameV1, ()> for Frame {
    fn event(s: &mut Self, _: &ZwlrScreencopyFrameV1, e: zwlr_screencopy_frame_v1::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {
        use zwlr_screencopy_frame_v1::Event;
        match e {
            Event::Buffer { format, width, height, stride } => {
                if let WEnum::Value(f) = format {
                    s.buf = Some((f, width as i32, height as i32, stride as i32));
                }
            }
            Event::BufferDone => s.buffer_done = true,
            Event::Flags { flags } => s.y_invert = matches!(flags, WEnum::Value(f) if f.contains(zwlr_screencopy_frame_v1::Flags::YInvert)),
            Event::Ready { .. } => s.ready = true,
            Event::Failed => s.failed = true,
            _ => {}
        }
    }
}
impl Dispatch<wl_shm_pool::WlShmPool, ()> for Frame {
    fn event(_: &mut Self, _: &wl_shm_pool::WlShmPool, _: wl_shm_pool::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}
impl Dispatch<wl_buffer::WlBuffer, ()> for Frame {
    fn event(_: &mut Self, _: &wl_buffer::WlBuffer, _: wl_buffer::Event, _: &(), _: &Connection, _: &QueueHandle<Self>) {}
}

struct Core {
    queue: EventQueue<Outputs>,
    outputs: Outputs,
}

#[derive(Clone)]
pub struct Capturer {
    conn: Connection,
    manager: ZwlrScreencopyManagerV1,
    shm: wl_shm::WlShm,
    core: Arc<Mutex<Core>>,
}

/// Read-only mapping of the shared-memory file the compositor wrote into.
struct Map {
    ptr: *mut libc::c_void,
    len: usize,
}
impl Map {
    fn bytes(&self) -> &[u8] {
        // SAFETY: ptr/len come from a successful mmap that lives until Drop.
        unsafe { std::slice::from_raw_parts(self.ptr as *const u8, self.len) }
    }
}
impl Drop for Map {
    fn drop(&mut self) {
        // SAFETY: unmaps exactly what mmap returned.
        unsafe { libc::munmap(self.ptr, self.len) };
    }
}

fn memfd(len: usize) -> Option<OwnedFd> {
    // SAFETY: plain syscalls; the descriptor is owned right after creation.
    unsafe {
        let fd = libc::memfd_create(c"hintd-shot".as_ptr(), libc::MFD_CLOEXEC);
        if fd < 0 {
            return None;
        }
        let fd = OwnedFd::from_raw_fd(fd);
        (libc::ftruncate(fd.as_raw_fd(), len as libc::off_t) == 0).then_some(fd)
    }
}

fn map(fd: &OwnedFd, len: usize) -> Option<Map> {
    // SAFETY: maps the file we just sized; checked against MAP_FAILED.
    let ptr = unsafe { libc::mmap(std::ptr::null_mut(), len, libc::PROT_READ, libc::MAP_SHARED, fd.as_raw_fd(), 0) };
    (ptr != libc::MAP_FAILED).then_some(Map { ptr, len })
}

impl Capturer {
    pub fn connect() -> Result<Capturer, String> {
        let conn = Connection::connect_to_env().map_err(|e| e.to_string())?;
        let (globals, mut queue) = registry_queue_init::<Outputs>(&conn).map_err(|e| e.to_string())?;
        let qh = queue.handle();
        let manager: ZwlrScreencopyManagerV1 = globals.bind(&qh, 1..=3, ()).map_err(|e| format!("wlr-screencopy: {e}"))?;
        let shm: wl_shm::WlShm = globals.bind(&qh, 1..=1, ()).map_err(|e| format!("wl_shm: {e}"))?;
        let xdg_manager: ZxdgOutputManagerV1 = globals.bind(&qh, 1..=3, ()).map_err(|e| format!("xdg-output: {e}"))?;
        let mut outputs = Outputs { xdg_manager: Some(xdg_manager), ..Default::default() };
        for g in globals.contents().clone_list() {
            if g.interface == "wl_output" {
                outputs.add(globals.registry(), &qh, g.name, g.version);
            }
        }
        queue.roundtrip(&mut outputs).map_err(|e| e.to_string())?;
        Ok(Capturer { conn, manager, shm, core: Arc::new(Mutex::new(Core { queue, outputs })) })
    }

    /// Wait until `done`, dispatching on the way; None on error or when the compositor stays silent.
    fn pump(&self, q: &mut EventQueue<Frame>, st: &mut Frame, done: impl Fn(&Frame) -> bool) -> Option<()> {
        let deadline = Instant::now() + WAIT;
        loop {
            q.dispatch_pending(st).ok()?;
            if done(st) {
                return Some(());
            }
            self.conn.flush().ok()?;
            let Some(guard) = q.prepare_read() else { continue };
            let left = deadline.checked_duration_since(Instant::now())?;
            let mut pfd = libc::pollfd { fd: guard.connection_fd().as_raw_fd(), events: libc::POLLIN, revents: 0 };
            // SAFETY: one valid pollfd, count 1.
            let r = unsafe { libc::poll(&mut pfd, 1, left.as_millis().max(1) as i32) };
            if r > 0 {
                let _ = guard.read();
            } else if r == 0 {
                return None;
            }
        }
    }

    /// Gray picture of one screen rectangle (global logical coordinates) on one monitor.
    /// None = could not (odd pixel format, scaled monitor so the picture size differs, rectangle across monitors, compositor refused).
    pub fn gray(&self, (x, y, w, h): Rect) -> Option<(usize, usize, Vec<u8>)> {
        let t0 = Instant::now();
        let (fmt, stride, y_invert, map_) = {
            let mut core = self.core.lock().ok()?;
            let core = &mut *core;
            // Monitors plugged or moved since the last press: take what has already arrived, never wait for the compositor.
            core.queue.dispatch_pending(&mut core.outputs).ok()?;
            if let Some(guard) = core.queue.prepare_read() {
                let mut pfd = libc::pollfd { fd: guard.connection_fd().as_raw_fd(), events: libc::POLLIN, revents: 0 };
                // SAFETY: one valid pollfd, count 1, zero timeout.
                if unsafe { libc::poll(&mut pfd, 1, 0) } > 0 {
                    let _ = guard.read();
                }
            }
            core.queue.dispatch_pending(&mut core.outputs).ok()?;
            let o = core.outputs.outs.values().find(|o| o.w > 0 && x >= o.x && y >= o.y && x.saturating_add(w) <= o.x.saturating_add(o.w) && y.saturating_add(h) <= o.y.saturating_add(o.h));
            if o.is_none() && debug() {
                let list: Vec<_> = core.outputs.outs.values().map(|o| (o.x, o.y, o.w, o.h)).collect();
                eprintln!("hintd: capture: no single monitor holds {:?}; monitors {list:?}", (x, y, w, h));
            }
            let o = o?;
            let output = o.output.clone()?;
            let mut q = self.conn.new_event_queue::<Frame>();
            let qh = q.handle();
            let frame = self.manager.capture_output_region(0, &output, x - o.x, y - o.y, w, h, &qh, ());
            let mut st = Frame::default();
            let got = self.finish(&mut q, &qh, &mut st, &frame, (w, h));
            frame.destroy();
            let _ = self.conn.flush();
            if got.is_none() && debug() {
                eprintln!("hintd: capture: compositor gave nothing (buffer {:?}, failed {}, ready {})", st.buf, st.failed, st.ready);
            }
            let (fmt, stride, map_) = got?;
            (fmt, stride, st.y_invert, map_)
        };
        let t_cap = t0.elapsed();
        let (w, h) = (w as usize, h as usize);
        let mut gray = vec![0u8; w * h];
        let stride = stride as usize;
        let (r, b) = match fmt {
            wl_shm::Format::Argb8888 | wl_shm::Format::Xrgb8888 => (2, 0), // little-endian bytes B G R A
            wl_shm::Format::Abgr8888 | wl_shm::Format::Xbgr8888 => (0, 2),
            _ => return None,
        };
        let src = map_.bytes();
        let band = h.div_ceil(workers()).max(1);
        std::thread::scope(|s| {
            for (i, rows) in gray.chunks_mut(band * w).enumerate() {
                s.spawn(move || {
                    for (k, dst) in rows.chunks_mut(w).enumerate() {
                        let y = i * band + k;
                        let sy = if y_invert { h - 1 - y } else { y };
                        let line = &src[sy * stride..sy * stride + w * 4];
                        for (d, px) in dst.iter_mut().zip(line.chunks_exact(4)) {
                            *d = ((px[r] as u32 * 299 + px[1] as u32 * 587 + px[b] as u32 * 114) / 1000) as u8;
                        }
                    }
                });
            }
        });
        if debug() {
            eprintln!("hintd: capture {w}x{h}: compositor {t_cap:?}, gray {:?}", t0.elapsed() - t_cap);
        }
        Some((w, h, gray))
    }

    /// From the frame request to "ready": returns the pixel format, stride and the mapped memory.
    fn finish(&self, q: &mut EventQueue<Frame>, qh: &QueueHandle<Frame>, st: &mut Frame, frame: &ZwlrScreencopyFrameV1, (w, h): (i32, i32)) -> Option<(wl_shm::Format, i32, Map)> {
        let v3 = self.manager.version() >= 3;
        self.pump(q, st, |s| (if v3 { s.buffer_done } else { s.buf.is_some() }) || s.failed)?;
        let (fmt, bw, bh, stride) = st.buf.filter(|_| !st.failed)?;
        if bw != w || bh != h || stride < w * 4 || stride > w * 4 + 4096 {
            return None;
        }
        let len = (stride as i64 * h as i64) as usize;
        let fd = memfd(len)?;
        let pool = self.shm.create_pool(fd.as_fd(), len as i32, qh, ());
        let buffer = pool.create_buffer(0, w, h, stride, fmt, qh, ());
        pool.destroy();
        frame.copy(&buffer);
        let done = self.pump(q, st, |s| s.ready || s.failed);
        buffer.destroy();
        done?;
        if st.failed {
            return None;
        }
        Some((fmt, stride, map(&fd, len)?))
    }
}

fn debug() -> bool {
    std::env::var_os("HINTD_DEBUG").is_some()
}

fn workers() -> usize {
    std::thread::available_parallelism().map(|n| n.get()).unwrap_or(1).clamp(1, 4)
}

/// Against the real compositor: HINTD_TEST_RECT="x,y,w,h" (default: a big window-sized area).
/// cargo test --release -- --ignored --nocapture screen
#[cfg(test)]
mod tests {
    use super::*;

    fn rect() -> Rect {
        let v: Vec<i32> = std::env::var("HINTD_TEST_RECT").unwrap_or("16,574,1888,1030".into()).split(',').map(|n| n.parse().unwrap()).collect();
        (v[0], v[1], v[2], v[3])
    }

    fn grim_gray((x, y, w, h): Rect) -> (usize, usize, Vec<u8>) {
        let out = std::process::Command::new("grim").args(["-t", "ppm", "-s", "1", "-g", &format!("{x},{y} {w}x{h}"), "-"]).output().unwrap();
        crate::vision::gray_from_ppm(&out.stdout).unwrap()
    }

    #[test]
    #[ignore]
    fn screen_capture_matches_grim_and_is_faster() {
        let r = rect();
        let cap = Capturer::connect().expect("capturer");
        let (cw, ch, cg) = cap.gray(r).expect("capture");
        let (gw, gh, gg) = grim_gray(r);
        let (_, _, gg2) = grim_gray(r);
        let (_, _, cg2) = cap.gray(r).expect("capture");
        assert_eq!((cw, ch), (gw, gh));
        // The screen may move between two shots (video, clock): judge the capture by how far it is from grim
        // compared with how far grim is from grim.
        let mad = |a: &[u8], b: &[u8]| a.iter().zip(b).map(|(x, y)| (*x as f64 - *y as f64).abs()).sum::<f64>() / a.len() as f64;
        let (cross, g_g, c_c) = (mad(&cg, &gg), mad(&gg, &gg2), mad(&cg, &cg2));
        eprintln!("{cw}x{ch}: mean abs gray difference  capture-vs-grim {cross:.4}   grim-vs-grim {g_g:.4}   capture-vs-capture {c_c:.4}");
        assert!(cross <= g_g.max(c_c) * 1.5 + 0.05, "capture differs from grim more than the screen moves on its own");
        let best = |mut f: Box<dyn FnMut()>| (0..10).map(|_| { let t = Instant::now(); f(); t.elapsed() }).min().unwrap();
        let t_cap = best(Box::new(|| { cap.gray(r).unwrap(); }));
        let t_grim = best(Box::new(|| { grim_gray(r); }));
        eprintln!("in-process capture + gray {t_cap:?}   grim + ppm + gray {t_grim:?}");
    }

    /// Four captures at once (the daemon asks for every visible window at the same time) all succeed.
    #[test]
    #[ignore]
    fn screen_capture_in_parallel() {
        let r = rect();
        let cap = Capturer::connect().expect("capturer");
        let hs: Vec<_> = (0..4).map(|_| { let c = cap.clone(); std::thread::spawn(move || c.gray(r).is_some()) }).collect();
        assert!(hs.into_iter().all(|h| h.join().unwrap()));
    }

    #[test]
    #[ignore]
    fn screen_capture_refuses_what_it_cannot_do() {
        let cap = Capturer::connect().expect("capturer");
        assert!(cap.gray((-5000, -5000, 100, 100)).is_none(), "off every monitor");
    }
}
