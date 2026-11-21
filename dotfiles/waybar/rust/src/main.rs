//! wbw: waybar widgets in one small binary.
//!
//!   wbw clev|hintdrive [--click L|R | --prompt]
//!   wbw mic
//!   wbw host [--notify] <host>...
//!   wbw claude [--focus]

mod claude;
mod common;
mod flow;
mod host;
mod mic;

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let rest: Vec<&str> = args.iter().skip(1).map(String::as_str).collect();
    match args.first().map(String::as_str) {
        Some(n @ ("clev" | "hintdrive")) => {
            let f = flow::Flow::new(if n == "clev" { "clev" } else { "hintdrive" });
            match rest.as_slice() {
                ["--click", b] => f.click(b),
                ["--prompt"] => f.hotkey(),
                _ => f.watch(),
            }
        }
        Some("mic") => mic::run(),
        Some("host") => host::run(&args[1..]),
        Some("claude") if rest == ["--focus"] => claude::focus(),
        Some("claude") => claude::run(),
        _ => {
            eprintln!("usage: wbw clev|hintdrive|mic|host|claude [args]");
            std::process::exit(2);
        }
    }
}
