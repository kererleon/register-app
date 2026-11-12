//! System notifications for what changed (Mac, Windows).

use register_core::changes::Change;

/// More than this many changes become one summary, so a long absence
/// does not end in a flood of notifications.
const MAX_SINGLE: usize = 4;

pub fn announce(changes: &[Change]) {
    if changes.is_empty() {
        return;
    }
    #[cfg(target_os = "macos")]
    let _ = notify_rust::set_application("com.webandgrow.register-rust");
    if changes.len() > MAX_SINGLE {
        let titles: Vec<&str> = changes.iter().take(6).map(|c| c.title.as_str()).collect();
        show(&format!("{} Neuigkeiten im Register", changes.len()), &titles.join("\n"));
    } else {
        for c in changes {
            show(&c.title, &c.body);
        }
    }
}

#[cfg(not(target_os = "android"))]
fn show(title: &str, body: &str) {
    let _ = notify_rust::Notification::new().appname("Register").summary(title).body(body).show();
}

#[cfg(target_os = "android")]
fn show(_title: &str, _body: &str) {}
