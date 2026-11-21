//! init.bash must not change how PROMPT_COMMAND reaches child processes.

use std::process::Command;

fn inner(prompt_command_env: &str, script: &str) -> String {
    let init = concat!(env!("CARGO_MANIFEST_DIR"), "/init.bash");
    let out = Command::new("bash")
        .args(["--norc", "-i", "-c", &format!("source {init}; {}", script.replace("INIT", init))])
        .env("BASH_SUGGEST", "1")
        .env("PROMPT_COMMAND", prompt_command_env)
        .env("XDG_RUNTIME_DIR", std::env::temp_dir())
        .output()
        .unwrap();
    String::from_utf8_lossy(&out.stdout).into_owned()
}

#[test]
fn exported_string_stays_exported_string() {
    let out = inner("history -a;__zoxide_hook", "bash -c 'echo \"child=$PROMPT_COMMAND\"'");
    assert_eq!(out.trim(), "child=history -a;__zoxide_hook;__bs_prompt");
}

#[test]
fn hook_added_once() {
    let out = inner("x", "source INIT; echo \"$PROMPT_COMMAND$PS0\"");
    assert_eq!(out.matches("__bs_prompt").count(), 1, "{out}");
}

#[test]
fn trailing_separator_is_not_doubled() {
    let out = inner("history -a; ", "echo \"$PROMPT_COMMAND\"");
    assert_eq!(out.trim(), "history -a;__bs_prompt");
}

#[test]
fn ps0_marker_added_once() {
    let out = inner("", "source INIT; echo \"$PS0\"");
    assert_eq!(out.matches("133;C").count(), 1, "{out}");
}
