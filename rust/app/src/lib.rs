// Register – Rust version. The window shows the data at once from the
// device; the register is asked in the background, all parts at the same
// time, and the window updates when the answers are there.

mod format;
mod notify;
mod settings;
mod view;

use std::cell::RefCell;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use register_core::client::{Client, Error};
use register_core::data::{Data, monday_of, today};
use register_core::schools;
use serde_json::json;
use slint::{ComponentHandle, ModelRc, SharedString, VecModel, Weak};

slint::include_modules!();

/// Android starts the app here instead of `main`.
#[cfg(target_os = "android")]
#[unsafe(no_mangle)]
fn android_main(app: slint::android::AndroidApp) {
    if let Some(dir) = app.internal_data_path() {
        settings::set_dir(dir);
    }
    slint::android::init(app).expect("Android backend");
    run().expect("Register");
}

/// Everything the window shows and the connection behind it.
pub struct State {
    pub data: Data,
    pub client: Option<Arc<Client>>,
    pub settings: settings::Settings,
    /// Weeks from the current one shown in the calendar.
    pub week_offset: i64,
    pub show_past: bool,
    /// 0 first, 1 second, 2 both semesters.
    pub semester: i32,
    remember: bool,
}

type Shared = Arc<Mutex<State>>;

fn data_path() -> PathBuf {
    settings::dir().join("data.json")
}

/// Runs [work] in the background, then shows the new state.
fn background(ui: &AppWindow, shared: &Shared, work: impl FnOnce(&Shared) -> Option<String> + Send + 'static) {
    let weak = ui.as_weak();
    let shared = shared.clone();
    std::thread::spawn(move || {
        let status = work(&shared);
        update(weak, shared, status);
    });
}

fn update(weak: Weak<AppWindow>, shared: Shared, status: Option<String>) {
    let _ = weak.upgrade_in_event_loop(move |ui| {
        let state = shared.lock().unwrap();
        view::apply(&ui, &state);
        let data = ui.global::<AppData>();
        data.set_busy(false);
        if let Some(status) = status {
            data.set_status(status.into());
        }
    });
}

/// Loads everything from the register and keeps it on the device.
fn refresh(shared: &Shared) -> Option<String> {
    let client = shared.lock().unwrap().client.clone()?;
    // Loaded into a copy, so the window stays usable meanwhile.
    let before = shared.lock().unwrap().data.clone();
    let mut data = before.clone();
    let report = data.refresh(&client);
    notify::announce(&register_core::changes::between(&before, &data, today()));
    let mut state = shared.lock().unwrap();
    state.data = data;
    if state.remember && !client.is_demo() {
        let _ = state.data.save(&data_path());
    }
    match report.error {
        None => Some(String::new()),
        Some(Error::NoInternet) => Some("Offline – gespeicherte Daten".into()),
        Some(e) => Some(format!("Nicht geladen: {} ({e})", report.failed.join(", "))),
    }
}

thread_local! {
    /// A login waiting for its second factor.
    static PENDING: RefCell<Option<(String, String, String, bool)>> = const { RefCell::new(None) };
}

fn login(ui: &AppWindow, shared: &Shared, url: String, user: String, pass: String, remember: bool, code: Option<String>) {
    let data = ui.global::<AppData>();
    data.set_busy(true);
    data.set_error(SharedString::new());
    let weak = ui.as_weak();
    let shared = shared.clone();
    std::thread::spawn(move || {
        let client = Arc::new(Client::new(&url, &user, &pass));
        let result = client.login(code.as_deref());
        let ok = result.is_ok();
        let (weak2, shared2) = (weak.clone(), shared.clone());
        let _ = weak.upgrade_in_event_loop(move |ui| {
            let data = ui.global::<AppData>();
            match result {
                Ok(config) => {
                    let mut state = shared2.lock().unwrap();
                    // Another account: forget the other one's data.
                    if state.data.config.as_ref().is_some_and(|c| c.user_id != config.user_id) {
                        state.data = Data::default();
                    }
                    state.data.config = Some(config);
                    state.client = Some(client.clone());
                    state.remember = remember;
                    state.settings.school = schools::SCHOOLS
                        .iter()
                        .find(|(_, u)| *u == client.url())
                        .map(|(n, _)| n.to_string())
                        .unwrap_or_else(|| client.url().to_owned());
                    state.settings.save();
                    if remember && !client.is_demo() {
                        settings::store_login(client.url(), &user, &pass);
                    }
                    view::apply(&ui, &state);
                    data.set_two_factor(false);
                    data.set_logged_in(true);
                    data.set_status("Lade Daten …".into());
                }
                Err(Error::TwoFactorNeeded { wrong }) => {
                    data.set_busy(false);
                    data.set_two_factor(true);
                    data.set_error(if wrong { "Ungültiger Code".into() } else { SharedString::new() });
                    PENDING.with(|p| *p.borrow_mut() = Some((url, user, pass, remember)));
                }
                Err(e) => {
                    data.set_busy(false);
                    data.set_error(e.to_string().into());
                }
            }
        });
        if ok {
            let status = refresh(&shared);
            update(weak2, shared, status);
        }
    });
}

pub fn run() -> Result<(), slint::PlatformError> {
    let ui = AppWindow::new()?;
    let settings = settings::Settings::load();
    let theme = ui.global::<Theme>();
    theme.set_dark(settings.dark);
    theme.set_accent_choice(slint::Color::from_argb_encoded(settings.accent));

    let shared: Shared = Arc::new(Mutex::new(State {
        data: Data::default(),
        client: None,
        settings,
        week_offset: 0,
        show_past: false,
        semester: 2,
        remember: true,
    }));

    let data = ui.global::<AppData>();
    // For trying out notifications: REGISTER_TEST_NOTIFY=1.
    if std::env::var_os("REGISTER_TEST_NOTIFY").is_some() {
        notify::announce(&[register_core::changes::Change {
            title: "Supplenz am 13.11.".into(),
            body: "3. Stunde Mathematik: Test Vertretung".into(),
        }]);
    }
    // For trying out a page directly: REGISTER_PAGE=2 (grades).
    if let Some(page) = std::env::var("REGISTER_PAGE").ok().and_then(|p| p.parse().ok()) {
        ui.set_page(page);
    }

    // Saved data is shown at once. The saved login is read in the background:
    // the system's secure store can be slow or ask for permission, and the
    // window must not wait for it.
    if let Some(saved) = Data::load(&data_path()) {
        let mut state = shared.lock().unwrap();
        state.data = saved;
        view::apply(&ui, &state);
        data.set_logged_in(true);
    }
    {
        let weak = ui.as_weak();
        let shared = shared.clone();
        std::thread::spawn(move || match settings::load_login() {
            Some((url, user, pass)) => {
                shared.lock().unwrap().client = Some(Arc::new(Client::new(&url, &user, &pass)));
                let _ = weak.upgrade_in_event_loop(|ui| {
                    let data = ui.global::<AppData>();
                    data.set_logged_in(true);
                    data.set_status("Aktualisiere …".into());
                });
                let status = refresh(&shared);
                update(weak, shared, status);
            }
            None => {
                // No login: the saved data belongs to nobody any more.
                let _ = weak.upgrade_in_event_loop(|ui| ui.global::<AppData>().set_logged_in(false));
            }
        });
    }

    data.on_search_schools({
        let weak = ui.as_weak();
        move |query| {
            let found: Vec<SchoolItem> = if query.trim().chars().count() < 2 {
                Vec::new()
            } else {
                schools::search(&query)
                    .into_iter()
                    .take(30)
                    .map(|(name, url)| SchoolItem { name: name.into(), url: url.into() })
                    .collect()
            };
            weak.unwrap().global::<AppData>().set_schools(ModelRc::new(VecModel::from(found)));
        }
    });

    data.on_login({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |url, user, pass, remember| {
            login(&weak.unwrap(), &shared, url.into(), user.trim().into(), pass.into(), remember, None);
        }
    });

    data.on_submit_two_factor({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |code| {
            if let Some((url, user, pass, remember)) = PENDING.with(|p| p.borrow_mut().take()) {
                login(&weak.unwrap(), &shared, url, user, pass, remember, Some(code.trim().into()));
            }
        }
    });

    data.on_logout({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let ui = weak.unwrap();
            let mut state = shared.lock().unwrap();
            state.client = None;
            state.data = Data::default();
            settings::forget_login();
            let _ = std::fs::remove_file(data_path());
            view::apply(&ui, &state);
            let data = ui.global::<AppData>();
            data.set_logged_in(false);
            data.set_status(SharedString::new());
        }
    });

    data.on_refresh({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let ui = weak.unwrap();
            ui.global::<AppData>().set_status("Aktualisiere …".into());
            background(&ui, &shared, refresh);
        }
    });

    data.on_toggle_done({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |id, kind, done| {
            let ui = weak.unwrap();
            {
                // Shown at once; the register is told in the background.
                let mut state = shared.lock().unwrap();
                for hw in state.data.dashboard.iter_mut().flat_map(|d| d.homework.iter_mut()) {
                    if hw.id == id as i64 && format::kind_name(hw.kind) == kind.as_str() {
                        hw.checked = done;
                    }
                }
                view::apply(&ui, &state);
            }
            let kind = kind.to_string();
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                client
                    .send("api/student/dashboard/toggle_reminder", json!({ "id": id, "type": kind, "value": done }))
                    .err()
                    .map(|e| format!("Nicht gespeichert: {e}"))
            });
        }
    });

    data.on_set_show_past({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |show_past| {
            let mut state = shared.lock().unwrap();
            state.show_past = show_past;
            view::apply(&weak.unwrap(), &state);
        }
    });

    data.on_set_semester({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |semester| {
            let mut state = shared.lock().unwrap();
            state.semester = semester;
            view::apply(&weak.unwrap(), &state);
        }
    });

    data.on_open_subject({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |id| {
            let ui = weak.unwrap();
            let semesters: Vec<usize> = match shared.lock().unwrap().semester {
                0 => vec![0],
                1 => vec![1],
                _ => vec![0, 1],
            };
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                for semester in semesters {
                    if let Err(e) = data.load_subject_details(&client, id as i64, semester) {
                        return Some(e.to_string());
                    }
                }
                s.lock().unwrap().data = data;
                None
            });
        }
    });

    data.on_move_week({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |step| {
            let ui = weak.unwrap();
            let monday = {
                let mut state = shared.lock().unwrap();
                state.week_offset = if step == 0 { 0 } else { state.week_offset + step as i64 };
                view::apply(&ui, &state);
                monday_of(today()) + chrono::Duration::weeks(state.week_offset)
            };
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.load_week(&client, monday);
                s.lock().unwrap().data = data;
                result.err().map(|e| e.to_string())
            });
        }
    });

    data.on_mark_read({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |id| {
            let ui = weak.unwrap();
            {
                let mut state = shared.lock().unwrap();
                if let Some(m) = state.data.messages.iter_mut().find(|m| m.id == id as i64) {
                    m.read = true;
                }
                view::apply(&ui, &state);
            }
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                client.send("api/message/markAsRead", json!({ "messageId": id })).err().map(|e| e.to_string())
            });
        }
    });

    data.on_add_reminder({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |date, text| {
            let ui = weak.unwrap();
            let Some(date) = format::parse_date(&date, today()) else {
                ui.global::<AppData>().set_status("Datum bitte als TT.MM.JJJJ eingeben".into());
                return;
            };
            let text = text.trim().to_owned();
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.add_reminder(&client, date, &text);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => "Erinnerung eingetragen".into(),
                    Err(e) => format!("Nicht eingetragen: {e}"),
                })
            });
        }
    });

    data.on_delete_reminder({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |id| {
            let ui = weak.unwrap();
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.delete_reminder(&client, id as i64);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => "Erinnerung gelöscht".into(),
                    Err(e) => format!("Nicht gelöscht: {e}"),
                })
            });
        }
    });

    data.on_report_absence({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |from, to, first, last, reason, signature| {
            let ui = weak.unwrap();
            let today = today();
            let (Some(start), Some(end)) = (format::parse_date(&from, today), format::parse_date(&to, today)) else {
                ui.global::<AppData>().set_status("Datum bitte als TT.MM.JJJJ eingeben".into());
                return;
            };
            if end < start || last < first {
                ui.global::<AppData>().set_status("Das Ende liegt vor dem Anfang".into());
                return;
            }
            ui.global::<AppData>().set_busy(true);
            let (reason, signature) = (reason.to_string(), signature.to_string());
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.add_future_absence(&client, start, end, first, last, &reason, &signature);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => "Abwesenheit gemeldet".into(),
                    Err(e) => format!("Nicht gemeldet: {e}"),
                })
            });
        }
    });

    data.on_remove_future_absence({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |index| {
            let ui = weak.unwrap();
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.remove_future_absence(&client, index as usize);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => "Abwesenheit gelöscht".into(),
                    Err(e) => format!("Nicht gelöscht: {e}"),
                })
            });
        }
    });

    // The "now" card and the lesson markers follow the clock.
    let timer = slint::Timer::default();
    timer.start(slint::TimerMode::Repeated, std::time::Duration::from_secs(30), {
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            if let (Some(ui), Ok(state)) = (weak.upgrade(), shared.try_lock()) {
                view::apply_today(&ui, &state);
            }
        }
    });

    // Look for news every 15 minutes while the app is open.
    let reload = slint::Timer::default();
    reload.start(slint::TimerMode::Repeated, std::time::Duration::from_secs(15 * 60), {
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            if let Some(ui) = weak.upgrade() {
                background(&ui, &shared, refresh);
            }
        }
    });

    ui.run()?;

    // Remember the look for the next start.
    let mut state = shared.lock().unwrap();
    let theme = ui.global::<Theme>();
    state.settings.dark = theme.get_dark();
    state.settings.accent = theme.get_accent_choice().as_argb_encoded();
    state.settings.save();
    Ok(())
}
