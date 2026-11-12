// Register – Rust version. The window shows the data at once from the
// device; the register is asked in the background, all parts at the same
// time, and the window updates when the answers are there.

mod dart_random;
mod decor;
mod subject_icon_data;
mod subject_icons;
mod format;
mod photos;
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
use slint::{ComponentHandle, Model, ModelRc, SharedString, VecModel, Weak};

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
    pub show_cancelled: bool,
    pub sort_by_type: bool,
    pub last_page: i32,
    /// The grade calculator's grades: value, weight, description.
    pub calc: Vec<(i32, i32, Option<String>)>,
    /// The day shown in detail and the selected lesson.
    pub detail: Option<(chrono::NaiveDate, usize)>,
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
        let mut state = shared.lock().unwrap();
        view::apply(&ui, &mut state);
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
    // Teacher photos: the list from the school's website, then the photos of
    // this and next week's teachers.
    if !client.is_demo() {
        photos::ensure(client.url());
        let teachers: Vec<register_core::model::Teacher> =
            data.calendar.values().flat_map(|d| d.hours.iter().flat_map(|h| h.teachers.iter().cloned())).collect();
        photos::download(&teachers);
    }
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
        // The connection is stored right away: loading below needs it, and
        // must not wait for the window to have taken the login.
        if ok {
            shared.lock().unwrap().client = Some(client.clone());
        }
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
                    state.semester = config.current_semester.map(|c| c as i32 - 1).unwrap_or(2);
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
                    view::apply(&ui, &mut state);
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
    // For trying out the app without an account: REGISTER_DEMO=1 uses the
    // demo data in a folder of its own, the real data stays untouched.
    let demo = std::env::var_os("REGISTER_DEMO").is_some();
    if demo {
        settings::set_dir(std::env::temp_dir().join("register-rust-demo"));
    }
    let ui = AppWindow::new()?;
    let settings = settings::Settings::load();
    let theme = ui.global::<Theme>();
    theme.set_style(settings.style);
    // For trying out a look: REGISTER_STYLE=1 (brainrot).
    if let Some(style) = std::env::var("REGISTER_STYLE").ok().and_then(|s| s.parse().ok()) {
        theme.set_style(style);
    }
    theme.set_dark(settings.dark);
    theme.set_accent_choice(slint::Color::from_argb_encoded(settings.accent));

    let shared: Shared = Arc::new(Mutex::new(State {
        data: Data::default(),
        client: None,
        settings,
        week_offset: 0,
        show_past: false,
        semester: 2,
        show_cancelled: false,
        sort_by_type: false,
        detail: None,
        last_page: 0,
        calc: Vec::new(),
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
    // For trying out an opened subject: REGISTER_OPEN_SUBJECT=1.
    let open_subject: Option<usize> = std::env::var("REGISTER_OPEN_SUBJECT").ok().and_then(|v| v.parse().ok());
    if let Some(i) = open_subject {
        ui.global::<Nav>().set_open_subject(i as i32);
    }
    // For trying out a page directly: REGISTER_PAGE=2 (grades).
    if let Some(page) = std::env::var("REGISTER_PAGE").ok().and_then(|p| p.parse().ok()) {
        ui.set_page(page);
    }

    // The background's emojis, stars and stickers for the window's size;
    // a new look also changes the calendar tiles (photos or icons).
    ui.global::<Deco>().on_resized({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |w, h| {
            if let Ok(mut state) = shared.try_lock() {
                let style = weak.unwrap().global::<Theme>().get_style();
                if state.settings.style != style {
                    state.settings.style = style;
                    state.settings.save();
                    view::apply(&weak.unwrap(), &mut state);
                }
            }
            let ui = weak.unwrap();
            let theme = ui.global::<Theme>();
            let d = decor::decorate(theme.get_style(), theme.get_dark(), w as f64, h as f64);
            let deco = ui.global::<Deco>();
            deco.set_stripes(d.stripes.into());
            deco.set_items(decor::model(d.items));
            deco.set_flag_height(d.flag_height);
            deco.set_flag_star(d.flag_star.into());
        }
    });

    // Saved data is shown at once. The saved login is read in the background:
    // the system's secure store can be slow or ask for permission, and the
    // window must not wait for it.
    if let Some(saved) = Data::load(&data_path()) {
        let mut state = shared.lock().unwrap();
        // For trying out the detail card: REGISTER_SELECT=3,0 (Thursday, first lesson).
        if let Some((day, lesson)) = std::env::var("REGISTER_SELECT").ok().and_then(|v| {
            let (a, b) = v.split_once(',')?;
            Some((a.parse::<i64>().ok()?, b.parse::<usize>().ok()?))
        }) {
            state.detail = Some((monday_of(today()) + chrono::Duration::days(day), lesson));
        }
        state.semester = saved.config.as_ref().and_then(|c| c.current_semester).map(|c| c as i32 - 1).unwrap_or(2);
        state.data = saved;
        view::apply(&ui, &mut state);
        data.set_logged_in(true);
    }
    if !demo {
        let weak = ui.as_weak();
        let shared = shared.clone();
        std::thread::spawn(move || match settings::load_login() {
            Some((url, user, pass)) => {
                shared.lock().unwrap().client = Some(Arc::new(Client::new(&url, &user, &pass)));
                if let Some(i) = open_subject {
                    let shared = shared.clone();
                    let weak = weak.clone();
                    std::thread::spawn(move || {
                        let (client, id) = {
                            let s = shared.lock().unwrap();
                            (s.client.clone(), s.data.subjects.get(i).map(|s| s.id))
                        };
                        if let (Some(client), Some(id)) = (client, id) {
                            let mut data = shared.lock().unwrap().data.clone();
                            let _ = data.load_subject_details(&client, id, 0);
                            shared.lock().unwrap().data = data;
                            update(weak, shared, None);
                        }
                    });
                }
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
            view::apply(&ui, &mut state);
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
                view::apply(&ui, &mut state);
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
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_set_semester({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |semester| {
            let mut state = shared.lock().unwrap();
            state.semester = semester;
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_set_show_cancelled({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |show| {
            let mut state = shared.lock().unwrap();
            state.show_cancelled = show;
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_set_sort_by_type({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |sort| {
            let mut state = shared.lock().unwrap();
            state.sort_by_type = sort;
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_forecast({
        let shared = shared.clone();
        move |id, target, weight| {
            let state = shared.lock().unwrap();
            let semester = match state.semester {
                0 => register_core::model::Semester::First,
                1 => register_core::model::Semester::Second,
                _ => register_core::model::Semester::All,
            };
            let Some(subject) = state.data.subjects.iter().find(|s| s.id == id as i64) else {
                return ForecastResult { kind: 0, needed: SharedString::new(), needed_value: 0.0 };
            };
            match register_core::grades::forecast(subject, semester, target as f64, weight) {
                register_core::grades::Forecast::Safe => ForecastResult { kind: 0, needed: SharedString::new(), needed_value: 0.0 },
                register_core::grades::Forecast::Impossible => {
                    ForecastResult { kind: 1, needed: SharedString::new(), needed_value: 0.0 }
                }
                register_core::grades::Forecast::Needs(g) => ForecastResult {
                    kind: 2,
                    needed: register_core::grades::format_steps(g).into(),
                    needed_value: g as f32,
                },
            }
        }
    });

    data.on_set_thick({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |line, thick| {
            let mut state = shared.lock().unwrap();
            let name = weak.unwrap().global::<AppData>().get_chart().row_data(line as usize).map(|l| l.name.to_string());
            if let Some(name) = name {
                state.settings.subject_thick.insert(name, thick);
                state.settings.save();
                view::apply(&weak.unwrap(), &mut state);
            }
        }
    });

    data.on_calc_valid_grade(|t| register_core::grades::parse_input(&t).is_some());
    data.on_calc_valid_weight(|t| t.trim().parse::<i32>().is_ok_and(|w| (0..=1000).contains(&w)));

    data.on_calc_add({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |grade, weight| {
            let (Some(g), Ok(w)) = (register_core::grades::parse_input(&grade), weight.trim().parse::<i32>()) else { return };
            let mut state = shared.lock().unwrap();
            state.calc.push((g, w, None));
            let ui = weak.unwrap();
            view::apply_calculator(&ui.global::<AppData>(), &state);
        }
    });

    data.on_calc_set({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |i, grade, weight| {
            let (Some(g), Ok(w)) = (register_core::grades::parse_input(&grade), weight.trim().parse::<i32>()) else { return };
            let mut state = shared.lock().unwrap();
            if let Some(entry) = state.calc.get_mut(i as usize) {
                // An edited grade shows no description any more.
                *entry = (g, w, None);
            }
            let ui = weak.unwrap();
            let pairs: Vec<(i32, i32)> = state.calc.iter().map(|(g, w, _)| (*g, *w)).collect();
            ui.global::<AppData>().set_calc_average(register_core::grades::calculator_average(&pairs).into());
        }
    });

    data.on_calc_remove({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |i| {
            let mut state = shared.lock().unwrap();
            if (i as usize) < state.calc.len() {
                state.calc.remove(i as usize);
            }
            let ui = weak.unwrap();
            view::apply_calculator(&ui.global::<AppData>(), &state);
        }
    });

    // The grades of a subject and semester, without cancelled ones.
    fn importable(state: &State, subject: i32, semester: i32) -> Vec<(i32, i32, Option<String>)> {
        let Some(s) = state.data.subjects.get(subject as usize) else { return Vec::new() };
        let semester = match semester {
            0 => register_core::model::Semester::First,
            1 => register_core::model::Semester::Second,
            _ => register_core::model::Semester::All,
        };
        register_core::grades::grades_of(s, semester)
            .filter(|g| !g.cancelled)
            .filter_map(|g| Some((g.value?, g.weight_percent, Some(format!("{} · {}", s.name, g.kind)))))
            .collect()
    }

    data.on_calc_import_preview({
        let shared = shared.clone();
        move |subject, semester| importable(&shared.lock().unwrap(), subject, semester).len() as i32
    });

    data.on_calc_import({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |subject, semester| {
            let mut state = shared.lock().unwrap();
            let grades = importable(&state, subject, semester);
            state.calc = grades;
            let ui = weak.unwrap();
            view::apply_calculator(&ui.global::<AppData>(), &state);
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
                view::apply(&ui, &mut state);
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

    data.on_select_lesson({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |day, lesson| {
            let mut state = shared.lock().unwrap();
            let monday = monday_of(today()) + chrono::Duration::weeks(state.week_offset);
            // The week's days as shown (Saturday only with lessons).
            let date = monday + chrono::Duration::days(day as i64);
            state.detail = Some((date, lesson as usize));
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_detail_move({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |step| {
            let ui = weak.unwrap();
            let target = {
                let mut state = shared.lock().unwrap();
                let Some((date, _)) = state.detail else { return };
                let target = date + chrono::Duration::days(step as i64);
                state.detail = Some((target, usize::MAX));
                view::apply(&ui, &mut state);
                (!state.data.calendar.contains_key(&target)).then(|| monday_of(target))
            };
            // A day of another week: load that week.
            if let Some(monday) = target {
                background(&ui, &shared, move |s| {
                    let client = s.lock().unwrap().client.clone()?;
                    let mut data = s.lock().unwrap().data.clone();
                    let result = data.load_week(&client, monday);
                    s.lock().unwrap().data = data;
                    result.err().map(|e| e.to_string())
                });
            }
        }
    });

    data.on_close_detail({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move || {
            let mut state = shared.lock().unwrap();
            state.detail = None;
            view::apply(&weak.unwrap(), &mut state);
        }
    });

    data.on_pick_teacher_image({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |card, teacher| {
            let teacher = {
                let state = shared.lock().unwrap();
                state.detail.and_then(|(date, _)| {
                    state.data.calendar.get(&date)?.hours.get(card as usize)?.teachers.get(teacher as usize).cloned()
                })
            };
            let Some(teacher) = teacher else { return };
            if let Some(path) = photos::pick_own(&teacher) {
                let mut state = shared.lock().unwrap();
                let key = register_core::teacher_photos::teacher_key(&teacher);
                if let Some(old) = state.settings.own_images.insert(key, path) {
                    let _ = std::fs::remove_file(old);
                }
                state.settings.save();
                view::apply(&weak.unwrap(), &mut state);
            }
        }
    });

    data.on_reset_teacher_image({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |card, teacher| {
            let mut state = shared.lock().unwrap();
            let teacher = state.detail.and_then(|(date, _)| {
                state.data.calendar.get(&date)?.hours.get(card as usize)?.teachers.get(teacher as usize).cloned()
            });
            if let Some(teacher) = teacher {
                if let Some(old) = state.settings.own_images.remove(&register_core::teacher_photos::teacher_key(&teacher)) {
                    let _ = std::fs::remove_file(old);
                }
                state.settings.save();
                view::apply(&weak.unwrap(), &mut state);
            }
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
                view::apply(&ui, &mut state);
            }
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                client.send("api/message/markAsRead", json!({ "messageId": id })).err().map(|e| e.to_string())
            });
        }
    });

    // Finds an entry of the homework page by its day and place.
    fn find_homework(state: &State, day: &str, index: i32) -> Option<(chrono::NaiveDate, register_core::model::Homework)> {
        let date = chrono::NaiveDate::parse_from_str(day, "%d.%m.%Y").ok()?;
        Some((date, state.data.homework_on(date).get(index as usize)?.clone()))
    }

    data.on_move_homework({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |day, index, y, m, d| {
            let ui = weak.unwrap();
            let Some((from, hw)) = find_homework(&shared.lock().unwrap(), &day, index) else { return };
            let Some(to) = chrono::NaiveDate::from_ymd_opt(y, m as u32, d as u32) else { return };
            if to == from {
                return;
            }
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.move_homework(&client, &hw, from, to);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => format!("Auf {} verschoben", format::long(to)),
                    Err(e) => format!("Die Aufgabe konnte nicht verschoben werden: {e}"),
                })
            });
        }
    });

    data.on_reset_move({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |day, index| {
            let ui = weak.unwrap();
            let Some((_, hw)) = find_homework(&shared.lock().unwrap(), &day, index) else { return };
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let result = data.reset_move(&client, &hw);
                s.lock().unwrap().data = data;
                Some(match result {
                    Ok(()) => "Verschiebung zurückgesetzt".into(),
                    Err(e) => format!("Die Erinnerung konnte nicht gelöscht werden: {e}"),
                })
            });
        }
    });

    data.on_homework_info({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |day, index| {
            let ui = weak.unwrap();
            let state = shared.lock().unwrap();
            let Some((date, hw)) = find_homework(&state, &day, index) else { return };
            let d = ui.global::<AppData>();
            d.set_info_title(hw.title.as_str().into());
            d.set_info_text(view::homework_info(&state.data, &hw, date).into());
            ui.global::<Nav>().set_info(true);
        }
    });

    data.on_page_shown({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |page| {
            let mut state = shared.lock().unwrap();
            // Leaving the homework page: what was new has been seen.
            if state.last_page == 1 && page != 1 && !state.data.unseen.is_empty() {
                state.data.unseen.clear();
                if state.remember {
                    let _ = state.data.save(&data_path());
                }
                view::apply(&weak.unwrap(), &mut state);
            }
            state.last_page = page;
            // The certificate is loaded each time it is opened (like Flutter).
            if page == 7 {
                drop(state);
                let worker = shared.clone();
                let w = weak.clone();
                std::thread::spawn(move || {
                    // Right after the start the login may still be on its way.
                    let mut client = None;
                    for _ in 0..40 {
                        client = worker.lock().unwrap().client.clone();
                        if client.is_some() {
                            break;
                        }
                        std::thread::sleep(std::time::Duration::from_millis(250));
                    }
                    let mut data = worker.lock().unwrap().data.clone();
                    let ok = client.is_some_and(|c| data.load_certificate(&c).is_ok());
                    if ok {
                        let mut state = worker.lock().unwrap();
                        state.data.certificate = data.certificate;
                        state.data.certificate_fetched = data.certificate_fetched;
                        let w2 = w.clone();
                        let _ = w2.upgrade_in_event_loop(|ui| ui.global::<AppData>().set_certificate_fetched("".into()));
                        if state.remember {
                            let _ = state.data.save(&data_path());
                        }
                        drop(state);
                        update(w, worker, None);
                    } else {
                        let fetched = worker.lock().unwrap().data.certificate.as_ref().and(data.certificate_fetched);
                        let _ = w.upgrade_in_event_loop(move |ui| {
                            let d = ui.global::<AppData>();
                            match fetched {
                                Some(t) => d.set_certificate_fetched(
                                    format!("Offline-Modus aktiv. Zuletzt synchronisiert {}.", view::time_ago(t)).into(),
                                ),
                                None => d.set_certificate_state(2),
                            }
                        });
                    }
                });
            }
        }
    });

    data.on_study_days({
        let shared = shared.clone();
        move |test, sessions| {
            let state = shared.lock().unwrap();
            let today = today();
            let days = view::tests_soon(&state.data, today)
                .get(test as usize)
                .map(|(date, _)| view::study_days(*date, today, sessions.max(1) as usize))
                .unwrap_or_default();
            ModelRc::new(VecModel::from(days.into_iter().map(|d| SharedString::from(view::day_short(d))).collect::<Vec<_>>()))
        }
    });

    data.on_create_study_plan({
        let weak = ui.as_weak();
        let shared = shared.clone();
        move |test, sessions| {
            let ui = weak.unwrap();
            let plan = {
                let state = shared.lock().unwrap();
                let today = today();
                view::tests_soon(&state.data, today).get(test as usize).map(|(date, h)| {
                    let what = [h.label.clone(), Some(h.title.clone())].into_iter().flatten().collect::<Vec<_>>().join(" – ");
                    let days = view::study_days(*date, today, sessions.max(1) as usize);
                    let n = days.len();
                    days.into_iter()
                        .enumerate()
                        .map(|(i, day)| (day, format!("Lernen {}/{n}: {what} (Test am {})", i + 1, view::day_short(*date))))
                        .collect::<Vec<_>>()
                })
            };
            let Some(plan) = plan else { return };
            background(&ui, &shared, move |s| {
                let client = s.lock().unwrap().client.clone()?;
                let mut data = s.lock().unwrap().data.clone();
                let n = plan.len();
                for (day, text) in plan {
                    if let Err(e) = data.add_reminder(&client, day, &text) {
                        s.lock().unwrap().data = data;
                        return Some(format!("Lernplan nicht vollständig: {e}"));
                    }
                }
                s.lock().unwrap().data = data;
                Some(format!("Lernplan mit {n} Erinnerungen eingetragen"))
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

    if demo {
        login(&ui, &shared, "https://vinzentinum.digitalesregister.it".into(), "demo-user-6540".into(), "demo".into(), false, None);
        if let Some(i) = open_subject {
            let weak = ui.as_weak();
            let shared = shared.clone();
            slint::Timer::single_shot(std::time::Duration::from_millis(800), move || {
                let id = shared.lock().unwrap().data.subjects.get(i).map(|s| s.id as i32);
                if let (Some(ui), Some(id)) = (weak.upgrade(), id) {
                    ui.global::<AppData>().invoke_open_subject(id);
                }
            });
        }
    }

    ui.run()?;

    // Remember the look for the next start.
    let mut state = shared.lock().unwrap();
    let theme = ui.global::<Theme>();
    state.settings.style = theme.get_style();
    state.settings.dark = theme.get_dark();
    state.settings.accent = theme.get_accent_choice().as_argb_encoded();
    state.settings.save();
    Ok(())
}
