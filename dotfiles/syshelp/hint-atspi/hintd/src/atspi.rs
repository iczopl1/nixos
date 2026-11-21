//! AT-SPI reader: pipelined D-Bus calls on the accessibility bus. Nothing is cached
//! except bus-name -> pid, which is pruned to the apps the registry lists on each press.
use futures_util::future::join_all;
use std::collections::{HashMap, HashSet};
use zbus::zvariant::{OwnedObjectPath, OwnedValue, Structure};
use zbus::Connection;

pub type Node = (String, String); // bus name, object path
pub type Rect = (i32, i32, i32, i32); // x, y, w, h

const ACC: &str = "org.a11y.atspi.Accessible";
const COMP: &str = "org.a11y.atspi.Component";
const COLL: &str = "org.a11y.atspi.Collection";
pub const WINDOW_COORDS: u32 = 1;
pub const SCREEN_COORDS: u32 = 0; // for windows whose window-coordinate size is stale (Qt on Wayland)

const SHOWING: u32 = 1 << 25;
const SENSITIVE: u32 = 1 << 24;
const ENABLED: u32 = 1 << 8;

// Atspi.Role numbers.
const ROLES: [i32; 16] = [43, 62, 88, 7, 44, 35, 8, 45, 33, 37, 11, 79, 40, 52, 51, 91];
const HIDE_CHECK: [i32; 5] = [35, 8, 45, 33, 37]; // menu items, menu, page tab
const ACTION_ROLES: [i32; 7] = [39, 85, 27, 26, 29, 32, 56]; // panel section image icon label list-item table-cell
const TABLE_CELL: i32 = 56;
const PRUNE_HIDDEN: [i32; 5] = [95, 82, 33, 41, 38]; // web doc, doc frame, menu, popup menu, tab list

pub const MAX_PER_SOURCE: usize = 300;
const RULE_CAP: i32 = MAX_PER_SOURCE as i32 + 100;
const MAX_GENERIC: (i32, i32) = (320, 64);
pub const MIN_SIZE: i32 = 6;

pub struct Atspi {
    conn: Connection,
    pids: HashMap<String, Option<i64>>,
}

pub struct Window {
    pub node: Node,
    pub extents: Rect,
    /// Same window in screen coordinates: Qt reports a stale size in window coordinates.
    pub screen: Rect,
}

fn nref(r: &(String, OwnedObjectPath)) -> Node {
    (r.0.clone(), r.1.to_string())
}

impl Atspi {
    pub async fn connect() -> zbus::Result<Atspi> {
        let session = Connection::session().await?;
        let addr: String = session
            .call_method(Some("org.a11y.Bus"), "/org/a11y/bus", Some("org.a11y.Bus"), "GetAddress", &())
            .await?
            .body()
            .deserialize()?;
        let conn = zbus::connection::Builder::address(addr.as_str())?.build().await?;
        Ok(Atspi { conn, pids: HashMap::new() })
    }

    async fn call<B, R>(&self, n: &Node, iface: &str, method: &str, body: &B) -> zbus::Result<R>
    where
        B: serde::Serialize + zbus::zvariant::DynamicType,
        R: serde::de::DeserializeOwned + zbus::zvariant::Type,
    {
        let msg = self
            .conn
            .call_method(Some(n.0.as_str()), n.1.as_str(), Some(iface), method, body)
            .await?;
        Ok(msg.body().deserialize::<R>()?)
    }

    pub async fn extents(&self, n: &Node, coords: u32) -> Option<Rect> {
        self.call::<_, Rect>(n, COMP, "GetExtents", &(coords,)).await.ok()
    }

    async fn children(&self, n: &Node) -> Vec<Node> {
        match self.call::<_, Vec<(String, OwnedObjectPath)>>(n, ACC, "GetChildren", &()).await {
            Ok(v) => v.iter().map(nref).collect(),
            Err(_) => vec![],
        }
    }

    async fn name(&self, n: &Node) -> Option<String> {
        let v: OwnedValue = self
            .call(n, "org.freedesktop.DBus.Properties", "Get", &(ACC, "Name"))
            .await
            .ok()?;
        String::try_from(v).ok()
    }

    async fn parent(&self, n: &Node) -> Option<Node> {
        let v: OwnedValue = self
            .call(n, "org.freedesktop.DBus.Properties", "Get", &(ACC, "Parent"))
            .await
            .ok()?;
        let s: Structure = v.try_into().ok()?;
        let r: (String, OwnedObjectPath) = s.try_into().ok()?;
        Some(nref(&r))
    }

    async fn role_state(&self, n: &Node) -> Option<(i32, u32)> {
        let role = self.call::<_, u32>(n, ACC, "GetRole", &());
        let state = self.call::<_, Vec<u32>>(n, ACC, "GetState", &());
        let (r, s) = futures_util::future::join(role, state).await;
        Some((r.ok()? as i32, *s.ok()?.first()?))
    }

    /// Accessible apps as (bus name, root, pid). Drops pids of names that left the bus.
    pub async fn apps(&mut self) -> Vec<(Node, i64)> {
        let reg: Node = ("org.a11y.atspi.Registry".into(), "/org/a11y/atspi/accessible/root".into());
        let roots = self.children(&reg).await;
        let live: HashSet<&String> = roots.iter().map(|r| &r.0).collect();
        self.pids.retain(|k, _| live.contains(k));
        let missing: Vec<String> = roots.iter().map(|r| r.0.clone()).filter(|b| !self.pids.contains_key(b)).collect();
        let conn = &self.conn;
        let got = join_all(missing.iter().map(|b| async move {
            let r = conn
                .call_method(Some("org.freedesktop.DBus"), "/org/freedesktop/DBus", Some("org.freedesktop.DBus"),
                             "GetConnectionUnixProcessID", &(b.as_str(),))
                .await
                .ok()
                .and_then(|m| m.body().deserialize::<u32>().ok());
            r.map(|p| p as i64)
        }))
        .await;
        for (b, p) in missing.into_iter().zip(got) {
            self.pids.insert(b, p);
        }
        roots.into_iter().filter_map(|r| self.pids.get(&r.0).copied().flatten().map(|p| (r, p))).collect()
    }

    /// Top-level windows of the given app roots, with their extents.
    pub async fn windows(&self, roots: &[Node]) -> Vec<Window> {
        let kids = join_all(roots.iter().map(|r| self.children(r))).await;
        let wins: Vec<Node> = kids.into_iter().flatten().collect();
        let (ext, scr) = futures_util::future::join(
            join_all(wins.iter().map(|w| self.extents(w, WINDOW_COORDS))),
            join_all(wins.iter().map(|w| self.extents(w, SCREEN_COORDS))),
        )
        .await;
        wins.into_iter()
            .zip(ext.into_iter().zip(scr))
            .filter_map(|(node, (e, s))| {
                e.or(s).map(|extents| Window { node, extents, screen: s.unwrap_or(extents) })
            })
            .collect()
    }

    pub async fn window_name(&self, w: &Window) -> Option<String> {
        self.name(&w.node).await
    }

    /// Clickable boxes of one window, in window coordinates, clipped by the caller.
    /// -> (boxes as (kind, rect), number of candidates the app exposed). None = no Collection.
    pub async fn collect(&self, win: &Node, coords: u32) -> Option<Vec<(u8, Rect)>> {
        let direct: Vec<i32> = ROLES.to_vec();
        let plain: Vec<i32> = direct.iter().copied().filter(|r| !HIDE_CHECK.contains(r)).collect();
        let hide: Vec<i32> = direct.iter().copied().filter(|r| HIDE_CHECK.contains(r)).collect();
        let generic: Vec<i32> = ACTION_ROLES.iter().copied().filter(|r| *r != TABLE_CELL).collect();
        let rules: [(Vec<i32>, bool, u8, bool, i32); 4] = [
            (plain, false, 1, false, RULE_CAP),
            (hide, false, 1, true, 100),
            (generic, true, 2, false, RULE_CAP),
            (vec![TABLE_CELL], true, 3, false, RULE_CAP),
        ];
        let t0 = std::time::Instant::now();
        let found = join_all(rules.iter().map(|(roles, action, _, _, cap)| self.matches(win, roles, *action, *cap))).await;
        let t_match = t0.elapsed();
        if found.iter().all(|f| f.is_none()) {
            return None;
        }
        let mut cands: Vec<(Node, u8, bool)> = vec![];
        for (f, (_, _, kind, hidecheck, cap)) in found.into_iter().zip(rules.iter()) {
            let f = f.unwrap_or_default();
            if f.len() >= *cap as usize {
                eprintln!("hintd: more than {cap} matches for one rule, the rest get no hint");
            }
            cands.extend(f.into_iter().map(|n| (n, *kind, *hidecheck)));
        }
        let (hidden, ext) = futures_util::future::join(
            self.hidden_set(cands.iter().filter(|c| c.2).map(|c| &c.0)),
            join_all(cands.iter().map(|c| self.extents(&c.0, coords))),
        )
        .await;
        if std::env::var_os("HINTD_DEBUG").is_some() {
            eprintln!("hintd: collect: matches {t_match:?}, hidden-check and extents together {:?} ({} candidates)", t0.elapsed() - t_match, cands.len());
        }
        let (cands, ext): (Vec<_>, Vec<_>) = cands.into_iter().zip(ext).filter(|(c, _)| !hidden.contains(&c.0)).unzip();
        Some(
            cands
                .into_iter()
                .zip(ext)
                .filter_map(|((_, kind, _), e)| e.map(|r| (kind, r)))
                .filter(|(kind, (_, _, w, h))| !(*kind == 2 && (*w > MAX_GENERIC.0 || *h > MAX_GENERIC.1)))
                .collect(),
        )
    }

    /// Showing lists, toolbars and trees that expose no children at all (Ferdium's service rail): the
    /// caller fills just those rectangles with picture-based boxes. At most 3, each at least 24x24.
    pub async fn holes(&self, win: &Node, coords: u32) -> Vec<Rect> {
        const HOLE_ROLES: [i32; 5] = [31, 63, 65, 34, 38]; // list, tool bar, tree, menu bar, tab list
        let Some(found) = self.matches(win, &HOLE_ROLES, false, 50).await else { return vec![] };
        let kids = join_all(found.iter().map(|n| self.children(n))).await;
        let empty: Vec<&Node> = found.iter().zip(kids).filter(|(_, k)| k.is_empty()).map(|(n, _)| n).collect();
        let ext = join_all(empty.iter().map(|n| self.extents(n, coords))).await;
        ext.into_iter().flatten().filter(|r| r.2 >= 24 && r.3 >= 24).take(3).collect()
    }

    async fn matches(&self, win: &Node, roles: &[i32], action: bool, cap: i32) -> Option<Vec<Node>> {
        let states = vec![(SHOWING | SENSITIVE) as i32, 0];
        let ifaces: Vec<String> = if action { vec!["action".into()] } else { vec![] };
        let rule = (states, 1i32, HashMap::<String, String>::new(), 1i32, role_bits(roles), 2i32, ifaces,
                    if action { 2i32 } else { 1i32 }, false);
        let r: Vec<(String, OwnedObjectPath)> = match self.call(win, COLL, "GetMatches", &(rule, 1u32, cap, true)).await {
            Ok(r) => r,
            Err(e) => {
                if std::env::var_os("HINTD_DEBUG").is_some() { eprintln!("hintd: GetMatches (action={action}) failed: {e}"); }
                return None;
            }
        };
        Some(r.iter().take(cap.max(0) as usize).map(nref).collect())
    }

    /// Items of closed menus / hidden tabs: Firefox reports them as showing while the menu is not.
    async fn hidden_set<'a>(&self, nodes: impl Iterator<Item = &'a Node>) -> HashSet<Node> {
        let nodes: Vec<&Node> = nodes.collect();
        let mut hidden = HashSet::new();
        if nodes.is_empty() {
            return hidden;
        }
        let mut memo: HashMap<Node, bool> = HashMap::new();
        let mut cur: Vec<(Node, Node)> = vec![]; // (origin, ancestor being looked at)
        let parents = join_all(nodes.iter().map(|n| self.parent(n))).await;
        for (n, p) in nodes.iter().zip(parents) {
            if let Some(p) = p {
                cur.push(((*n).clone(), p));
            }
        }
        for _ in 0..3 {
            let todo: Vec<Node> = cur.iter().map(|c| c.1.clone()).filter(|p| !memo.contains_key(p)).collect::<HashSet<_>>().into_iter().collect();
            let info = join_all(todo.iter().map(|p| futures_util::future::join(self.role_state(p), self.parent(p)))).await;
            let mut up: HashMap<Node, Option<Node>> = HashMap::new();
            for (p, (rs, par)) in todo.into_iter().zip(info) {
                let h = matches!(rs, Some((r, s)) if PRUNE_HIDDEN.contains(&r) && s & SHOWING == 0);
                memo.insert(p.clone(), h);
                up.insert(p, par);
            }
            let mut next = vec![];
            for (origin, anc) in cur {
                if memo.get(&anc).copied().unwrap_or(false) {
                    hidden.insert(origin);
                } else if let Some(Some(pp)) = up.get(&anc) {
                    next.push((origin, pp.clone()));
                }
            }
            cur = next;
            if cur.is_empty() {
                break;
            }
        }
        hidden
    }

    /// Level-by-level walk for toolkits without Collection (GTK4, Qt). Every level is
    /// asked at once; MAX_NODES bounds the work, MAX_CHILDREN a 100k-row list.
    pub async fn walk(&self, win: &Node, coords: u32) -> Vec<(u8, Rect)> {
        const MAX_NODES: usize = 6000;
        const MAX_CHILDREN: usize = 500;
        let mut level = vec![win.clone()];
        let mut seen = 0;
        let mut cands: Vec<(Node, u8)> = vec![];
        while !level.is_empty() && seen < MAX_NODES {
            level.truncate(MAX_NODES - seen);
            seen += level.len();
            let info = join_all(level.iter().map(|n| async move {
                let (rs, kids) = futures_util::future::join(self.role_state(n), self.children(n)).await;
                let rs = rs?;
                let mut kind = 0u8;
                let showing = rs.1 & SHOWING != 0;
                let usable = rs.1 & (ENABLED | SENSITIVE) != 0;
                if showing && usable {
                    if ROLES.contains(&rs.0) {
                        kind = 1;
                    } else if ACTION_ROLES.contains(&rs.0) && self.has_action(n).await {
                        kind = if rs.0 == TABLE_CELL { 3 } else { 2 };
                    }
                }
                let hidden = !showing && PRUNE_HIDDEN.contains(&rs.0);
                Some((kind, if hidden { vec![] } else { kids }))
            }))
            .await;
            let mut next = vec![];
            for (n, i) in level.into_iter().zip(info) {
                if let Some((kind, kids)) = i {
                    if kind != 0 {
                        cands.push((n, kind));
                    }
                    next.extend(kids.into_iter().take(MAX_CHILDREN));
                }
            }
            level = next;
        }
        let ext = join_all(cands.iter().map(|c| self.extents(&c.0, coords))).await;
        cands
            .into_iter()
            .zip(ext)
            .filter_map(|((_, kind), e)| e.map(|r| (kind, r)))
            .filter(|(kind, (_, _, w, h))| !(*kind == 2 && (*w > MAX_GENERIC.0 || *h > MAX_GENERIC.1)))
            .collect()
    }

    async fn has_action(&self, n: &Node) -> bool {
        match self.call::<_, Vec<String>>(n, ACC, "GetInterfaces", &()).await {
            Ok(i) => i.iter().any(|s| s.ends_with(".Action") || s == "Action"),
            Err(_) => false,
        }
    }
}


/// The Collection protocol takes roles as a bit set (4 words), not a list of numbers.
fn role_bits(roles: &[i32]) -> Vec<i32> {
    let mut w = [0u32; 4];
    for r in roles {
        w[(*r / 32) as usize] |= 1 << (*r % 32);
    }
    w.iter().map(|x| *x as i32).collect()
}
