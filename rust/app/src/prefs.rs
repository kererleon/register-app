//! The settings page: its switches, lists and dialogs.

use std::sync::Arc;

use register_core::client::Client;
use serde_json::json;
use slint::{ComponentHandle, SharedString};

use crate::{AppData, AppWindow, Nav, Prefs, Shared, Theme, data_path, photos, settings, view};

/// Whether [mode] (0 device, 1 light, 2 dark) means the dark look.
pub fn dark(mode: i32) -> bool {
    match mode {
        1 => false,
        2 => true,
        _ => device_is_dark(),
    }
}

#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn device_is_dark() -> bool {
    !matches!(dark_light::detect(), Ok(dark_light::Mode::Light))
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn device_is_dark() -> bool {
    true
}

fn show_background(ui: &AppWindow, path: Option<&str>) {
    let p = ui.global::<Prefs>();
    match path.and_then(|path| slint::Image::load_from_path(std::path::Path::new(path)).ok()) {
        Some(image) => {
            p.set_bg_image(image);
            p.set_has_bg(true);
        }
        None => {
            p.set_bg_image(slint::Image::default());
            p.set_has_bg(false);
        }
    }
}

/// Lets the user choose a picture; a copy no larger than any screen needs
/// is kept in the app's folder.
#[cfg(not(any(target_os = "android", target_os = "ios")))]
fn pick_background() -> Option<String> {
    let file = rfd::FileDialog::new()
        .set_title("Hintergrundbild")
        .add_filter("Bilder", &["jpg", "jpeg", "png", "webp", "gif"])
        .pick_file()?;
    let img = image::open(&file).ok()?;
    let dir = settings::dir();
    std::fs::create_dir_all(&dir).ok()?;
    // A new name each time, so the picture cache shows the new one.
    let path = dir.join(format!("background_{}.jpg", chrono::Local::now().timestamp_millis()));
    img.thumbnail(2400, 2400).to_rgb8().save_with_format(&path, image::ImageFormat::Jpeg).ok()?;
    Some(path.to_string_lossy().into_owned())
}

#[cfg(any(target_os = "android", target_os = "ios"))]
fn pick_background() -> Option<String> {
    None
}

fn open_url(url: &str) {
    // Only the app's own links, never started through a shell.
    if !url.starts_with("https://") {
        return;
    }
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(url).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("explorer").arg(url).spawn();
    #[cfg(all(unix, not(any(target_os = "macos", target_os = "android", target_os = "ios"))))]
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}

pub fn setup(ui: &AppWindow, shared: &Shared) {
    let p = ui.global::<Prefs>();
    {
        let state = shared.lock().unwrap();
        let st = &state.settings;
        p.set_remember(st.remember);
        p.set_save_data(st.save_data);
        p.set_delete_on_logout(st.delete_on_logout);
        p.set_theme_mode(st.theme_mode);
        p.set_color_borders(st.color_borders);
        p.set_calendar_color(st.calendar_color);
        p.set_tests_red(st.tests_red);
        p.set_mark_new(st.mark_new);
        p.set_dedupe(st.dedupe);
        p.set_ask_delete(st.ask_delete);
        p.set_show_diagram(st.show_diagram);
        p.set_show_average(st.show_average);
        p.set_show_photos(st.show_photos);
        p.set_nick_bar(st.nick_bar);
        p.set_bg_dim(st.background_dim);
        p.set_version(concat!("Rust-Version ", env!("CARGO_PKG_VERSION")).into());
        show_background(ui, st.background.as_deref());
    }

    p.on_changed({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let ui = weak.unwrap();
            let p = ui.global::<Prefs>();
            let theme = ui.global::<Theme>();
            let mut state = shared.lock().unwrap();
            // "Angemeldet bleiben": the login is stored or forgotten now.
            if p.get_remember() != state.settings.remember {
                match (&state.client, p.get_remember()) {
                    (Some(c), true) if !c.is_demo() => settings::store_login(c.url(), c.user(), c.password()),
                    (_, false) => settings::forget_login(),
                    _ => {}
                }
            }
            // "Daten lokal speichern": saved now, or removed from the device.
            if p.get_save_data() != state.settings.save_data {
                if p.get_save_data() {
                    let _ = state.data.save(&data_path());
                } else {
                    let _ = std::fs::remove_file(data_path());
                }
            }
            let dedupe = p.get_dedupe() && !state.settings.dedupe;
            let photos_on = p.get_show_photos() && !state.settings.show_photos;
            let st = &mut state.settings;
            st.remember = p.get_remember();
            st.save_data = p.get_save_data();
            st.delete_on_logout = p.get_delete_on_logout() && st.remember && st.save_data;
            st.theme_mode = p.get_theme_mode();
            st.color_borders = p.get_color_borders();
            st.calendar_color = p.get_calendar_color();
            st.tests_red = p.get_tests_red();
            st.mark_new = p.get_mark_new();
            st.dedupe = p.get_dedupe();
            st.ask_delete = p.get_ask_delete();
            st.show_diagram = p.get_show_diagram();
            st.show_average = p.get_show_average();
            st.show_photos = p.get_show_photos();
            st.nick_bar = p.get_nick_bar();
            st.background_dim = p.get_bg_dim();
            st.accent = theme.get_accent_choice().as_argb_encoded();
            st.dark = dark(st.theme_mode);
            st.save();
            p.set_delete_on_logout(st.delete_on_logout);
            theme.set_dark(st.dark);
            if dedupe {
                state.data.dedupe_dashboard();
            }
            view::apply(&ui, &mut state);
            drop(state);
            // Entries dropped before come back, photos are fetched.
            if (photos_on || !p.get_dedupe()) && ui.global::<AppData>().get_logged_in() {
                ui.global::<AppData>().invoke_refresh();
            }
        }
    });

    p.on_add_ignored({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |subject| {
            let mut state = shared.lock().unwrap();
            if !state.settings.ignored_subjects.iter().any(|s| s == subject.as_str()) {
                state.settings.ignored_subjects.push(subject.into());
            }
            state.settings.save();
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    p.on_remove_ignored({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |subject| {
            let mut state = shared.lock().unwrap();
            state.settings.ignored_subjects.retain(|s| s != subject.as_str());
            state.settings.save();
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    p.on_set_nick({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |old, subject, nick| {
            let (subject, nick) = (subject.trim().to_owned(), nick.trim().to_owned());
            if subject.is_empty() || nick.is_empty() {
                return;
            }
            let mut state = shared.lock().unwrap();
            let nicks = &mut state.settings.nicks;
            match nicks.iter().position(|(s, _)| s == old.as_str()).filter(|_| !old.is_empty()) {
                // Edited in place; a new one comes first.
                Some(i) => nicks[i] = (subject.clone(), nick),
                None => nicks.insert(0, (subject.clone(), nick)),
            }
            // One short name per subject: the newest wins.
            let mut seen = false;
            nicks.retain(|(s, _)| if *s == subject { !std::mem::replace(&mut seen, true) } else { true });
            state.settings.save();
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    p.on_remove_nick({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |subject| {
            let mut state = shared.lock().unwrap();
            state.settings.nicks.retain(|(s, _)| s != subject.as_str());
            state.settings.save();
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    p.on_set_subject_color({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |subject, color| {
            let mut state = shared.lock().unwrap();
            state.settings.subject_colors.insert(subject.into(), color.as_argb_encoded() & 0xff_ffff);
            state.settings.save();
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    p.on_set_staff_page({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |page| {
            let ui = weak.unwrap();
            let url = {
                let mut state = shared.lock().unwrap();
                let Some(url) = state.client.as_ref().map(|c| c.url().to_owned()) else { return };
                let Some(host) = url::Url::parse(&url).ok().and_then(|u| u.host_str().map(str::to_owned)) else { return };
                let mut page = page.trim().to_owned();
                if !page.is_empty() && !page.contains("://") {
                    page = format!("https://{page}");
                }
                if page.is_empty() {
                    state.settings.staff_pages.remove(&host);
                } else {
                    state.settings.staff_pages.insert(host, page);
                }
                state.settings.save();
                url
            };
            // Searched again with the new page.
            photos::forget(&url);
            ui.global::<AppData>().set_status(SharedString::from("Suche Fotos …"));
            ui.global::<AppData>().invoke_refresh();
        }
    });

    p.on_pick_background({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let Some(path) = pick_background() else { return };
            let ui = weak.unwrap();
            let mut state = shared.lock().unwrap();
            if let Some(old) = state.settings.background.replace(path.clone()) {
                let _ = std::fs::remove_file(old);
            }
            state.settings.save();
            show_background(&ui, Some(&path));
        }
    });

    p.on_remove_background({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let mut state = shared.lock().unwrap();
            if let Some(old) = state.settings.background.take() {
                let _ = std::fs::remove_file(old);
            }
            state.settings.save();
            show_background(&weak.unwrap(), None);
        }
    });

    p.on_open_url(|url| open_url(url.as_str()));

    // --- profile ---

    p.on_load_profile({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let ui = weak.unwrap();
            let p = ui.global::<Prefs>();
            if p.get_profile_name().is_empty() {
                p.set_profile_state(0);
            }
            let weak = weak.clone();
            let shared = shared.clone();
            std::thread::spawn(move || {
                let client = shared.lock().unwrap().client.clone();
                let profile = client.and_then(|c| c.send("api/profile/get", json!({})).ok()).filter(|v| v.is_object());
                let _ = weak.upgrade_in_event_loop(move |ui| {
                    let p = ui.global::<Prefs>();
                    let Some(v) = profile else {
                        // Offline: what was loaded before stays.
                        if p.get_profile_name().is_empty() {
                            p.set_profile_state(2);
                        }
                        return;
                    };
                    let text = |key: &str| register_core::json::text(&v[key]);
                    let name = text("name");
                    let parts: Vec<&str> = name.split_whitespace().collect();
                    let first = |w: &str| w.chars().next().map(|c| c.to_uppercase().to_string()).unwrap_or_default();
                    let initials = match parts.as_slice() {
                        [] => "?".to_owned(),
                        [one] => first(one),
                        [a, .., b] => first(a) + &first(b),
                    };
                    p.set_profile_initials(initials.into());
                    p.set_profile_user(format!("{} · {}", text("username"), text("roleName")).to_uppercase().into());
                    p.set_profile_email(text("email").into());
                    p.set_profile_notify(register_core::json::boolean(&v["notificationsEnabled"]).unwrap_or(false));
                    p.set_profile_name(name.into());
                    p.set_profile_state(1);
                });
            });
        }
    });

    p.on_set_notify_emails({
        let shared = shared.clone();
        move |on| {
            let shared = shared.clone();
            std::thread::spawn(move || {
                let client = shared.lock().unwrap().client.clone();
                if let Some(client) = client {
                    let _ = client.send("api/profile/updateNotificationSettings", json!({ "notificationsEnabled": on }));
                }
            });
        }
    });

    p.on_change_email({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |pass, email| {
            let ui = weak.unwrap();
            let p = ui.global::<Prefs>();
            p.set_profile_busy(true);
            p.set_profile_message(SharedString::new());
            let weak = weak.clone();
            let shared = shared.clone();
            let (pass, email) = (pass.to_string(), email.trim().to_owned());
            std::thread::spawn(move || {
                let client = shared.lock().unwrap().client.clone();
                let result = match client {
                    Some(c) => c.send("api/profile/updateProfile", json!({ "email": email, "password": pass })),
                    None => Err(register_core::client::Error::NoInternet),
                };
                let _ = weak.upgrade_in_event_loop(move |ui| {
                    let p = ui.global::<Prefs>();
                    p.set_profile_busy(false);
                    let (message, failed) = match result {
                        Ok(v) if v["error"].is_null() => {
                            (v["message"].as_str().unwrap_or("Email-Adresse geändert").to_owned(), false)
                        }
                        Ok(v) => (
                            format!("[{}]: {}", v["error"].as_str().unwrap_or("error"), v["message"].as_str().unwrap_or_default()),
                            true,
                        ),
                        Err(e) => (e.to_string(), true),
                    };
                    p.set_profile_message(message.into());
                    p.set_profile_failed(failed);
                    if !failed {
                        // Back to the profile, which shows the new address.
                        ui.global::<Nav>().set_profile(1);
                        p.invoke_load_profile();
                    }
                });
            });
        }
    });

    p.on_change_password({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |old, new| {
            let ui = weak.unwrap();
            let p = ui.global::<Prefs>();
            p.set_profile_busy(true);
            p.set_profile_message(SharedString::new());
            let weak = weak.clone();
            let shared = shared.clone();
            let (old, new) = (old.to_string(), new.to_string());
            std::thread::spawn(move || {
                let current = shared.lock().unwrap().client.clone();
                let result = match current {
                    Some(c) => {
                        // The old password is sent as typed, like the Flutter app.
                        let with_old = Client::new(c.url(), c.user(), &old);
                        with_old.change_password(&new).and_then(|()| {
                            // Logged in again with the new password.
                            let fresh = Arc::new(Client::new(c.url(), c.user(), &new));
                            fresh.login(None)?;
                            let mut state = shared.lock().unwrap();
                            if state.settings.remember {
                                settings::store_login(fresh.url(), fresh.user(), &new);
                            }
                            state.client = Some(fresh);
                            Ok(())
                        })
                    }
                    None => Err(register_core::client::Error::NoInternet),
                };
                let _ = weak.upgrade_in_event_loop(move |ui| {
                    let p = ui.global::<Prefs>();
                    p.set_profile_busy(false);
                    match result {
                        Ok(()) => {
                            p.set_profile_message("Passwort erfolgreich geändert".into());
                            p.set_profile_failed(false);
                            ui.global::<Nav>().set_profile(1);
                        }
                        Err(e) => {
                            p.set_profile_message(e.to_string().into());
                            p.set_profile_failed(true);
                        }
                    }
                });
            });
        }
    });
}
