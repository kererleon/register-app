//! The connection to a school's Digitales Register.

use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde_json::{Value, json};
use ureq::Agent;

use crate::demo;
use crate::model::Config;
use crate::parse;

const USER_AGENT: &str = concat!(
    "Register-Rust/",
    env!("CARGO_PKG_VERSION"),
    "; https://github.com/kererleon/register-app"
);

#[derive(Debug, Clone, PartialEq)]
pub enum Error {
    NoInternet,
    /// Wrong user name or password, or the session can not be renewed.
    LoggedOut(String),
    TwoFactorNeeded { wrong: bool },
    Server(String),
}

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Error::NoInternet => write!(f, "Keine Internetverbindung"),
            Error::LoggedOut(m) => write!(f, "{m}"),
            Error::TwoFactorNeeded { wrong: false } => write!(f, "Zweiter Faktor wird benötigt"),
            Error::TwoFactorNeeded { wrong: true } => write!(f, "Ungültiger Code"),
            Error::Server(m) => write!(f, "{m}"),
        }
    }
}

impl std::error::Error for Error {}

fn network_error(e: ureq::Error) -> Error {
    match e {
        ureq::Error::StatusCode(code) => Error::Server(format!("Der Server antwortet mit Fehler {code}")),
        ureq::Error::Io(_) | ureq::Error::HostNotFound | ureq::Error::ConnectionFailed | ureq::Error::Timeout(_) => {
            Error::NoInternet
        }
        other => Error::Server(other.to_string()),
    }
}

pub fn is_demo(url: &str, user: &str) -> bool {
    user == "demo-user-6540" && url.trim_end_matches('/') == "https://vinzentinum.digitalesregister.it"
}

/// "schule.digitalesregister.it/v2/login" -> "https://schule.digitalesregister.it".
pub fn fix_url(entered: &str) -> String {
    let mut url = entered.trim().to_owned();
    if !url.contains("://") {
        url = format!("https://{url}");
    }
    for suffix in ["/v2/login", "/v2/", "/v2", "/"] {
        if let Some(stripped) = url.strip_suffix(suffix) {
            url = stripped.to_owned();
        }
    }
    url
}

#[derive(Default)]
struct Session {
    logged_in: bool,
    /// The server ends sessions after a while without requests.
    logout_at: Option<Instant>,
    config: Option<Config>,
}

/// Can be shared between threads: requests run in parallel on one session.
pub struct Client {
    url: String,
    agent: Agent,
    user: String,
    pass: String,
    demo: bool,
    session: Mutex<Session>,
}

impl Client {
    pub fn new(url: &str, user: &str, pass: &str) -> Self {
        let url = fix_url(url);
        let agent: Agent = Agent::config_builder()
            .user_agent(USER_AGENT)
            .timeout_global(Some(Duration::from_secs(25)))
            .http_status_as_error(false)
            .build()
            .into();
        Client {
            demo: is_demo(&url, user),
            url,
            agent,
            user: user.to_owned(),
            pass: pass.to_owned(),
            session: Mutex::new(Session::default()),
        }
    }

    pub fn config(&self) -> Option<Config> {
        self.session.lock().unwrap().config.clone()
    }

    pub fn url(&self) -> &str {
        &self.url
    }
    pub fn user(&self) -> &str {
        &self.user
    }
    pub fn is_demo(&self) -> bool {
        self.demo
    }
    /// For keeping the login on the device when the user asks for it later.
    pub fn password(&self) -> &str {
        &self.pass
    }

    fn address(&self, path: &str) -> String {
        format!("{}/v2/{path}", self.url)
    }

    /// Logs in and reads the user's config. [two_factor] answers a
    /// [Error::TwoFactorNeeded].
    pub fn login(&self, two_factor: Option<&str>) -> Result<Config, Error> {
        let mut session = self.session.lock().unwrap();
        self.login_locked(&mut session, two_factor)
    }

    /// Logs in while holding the session lock, so parallel requests that
    /// find the session expired log in only once.
    fn login_locked(&self, session: &mut Session, two_factor: Option<&str>) -> Result<Config, Error> {
        if self.demo {
            session.logged_in = true;
            session.config = Some(demo::config());
            return Ok(demo::config());
        }
        self.agent.cookie_jar_lock().clear();
        let mut body = json!({ "username": self.user, "password": self.pass });
        if let Some(code) = two_factor {
            body["two_factor"] = json!(code);
        }
        let response: Value = self
            .agent
            .post(self.address("api/auth/login"))
            .send_json(&body)
            .map_err(network_error)?
            .body_mut()
            .read_json()
            .map_err(|e| Error::Server(e.to_string()))?;
        if response["loggedIn"].as_bool() != Some(true) {
            session.logged_in = false;
            let code = response["error"].as_str().unwrap_or_default();
            return Err(match code {
                "two_factor_needed" => Error::TwoFactorNeeded { wrong: false },
                "two_factor_wrong" => Error::TwoFactorNeeded { wrong: true },
                _ => Error::LoggedOut(
                    response["message"]
                        .as_str()
                        .filter(|m| !m.is_empty())
                        .unwrap_or("Anmeldung fehlgeschlagen")
                        .to_owned(),
                ),
            });
        }
        let start_page = self
            .agent
            .get(self.address(""))
            .call()
            .map_err(network_error)?
            .body_mut()
            .read_to_string()
            .map_err(|e| Error::Server(e.to_string()))?;
        let config = parse::config(&start_page)
            .ok_or_else(|| Error::Server("Die Startseite des Registers ist unbekannt".into()))?;
        session.logout_at = Some(Instant::now() + Duration::from_secs(config.auto_logout_seconds.max(60) as u64));
        session.logged_in = true;
        session.config = Some(config.clone());
        Ok(config)
    }

    fn ensure_logged_in(&self) -> Result<(), Error> {
        let mut session = self.session.lock().unwrap();
        let expired = session.logout_at.is_some_and(|t| Instant::now() >= t);
        if !session.logged_in || expired {
            self.login_locked(&mut session, None)?;
        }
        Ok(())
    }

    fn relogin(&self) -> Result<(), Error> {
        let mut session = self.session.lock().unwrap();
        self.login_locked(&mut session, None).map(|_| ())
    }

    fn post_raw(&self, path: &str, args: &Value) -> Result<String, Error> {
        self.agent
            .post(self.address(path))
            .send_json(args)
            .map_err(network_error)?
            .body_mut()
            .with_config()
            .limit(32 * 1024 * 1024)
            .read_to_string()
            .map_err(|e| Error::Server(e.to_string()))
    }

    /// Sends a request and returns the answer as JSON (or as a JSON string
    /// when it is not JSON). Logs in again when the session ended.
    pub fn send(&self, path: &str, args: Value) -> Result<Value, Error> {
        if self.demo {
            return Ok(demo::response(path, &args));
        }
        self.ensure_logged_in()?;
        let mut body = self.post_raw(path, &args)?;
        if is_logout_redirect(&body) {
            // Logged out by the server (e.g. logged in elsewhere): once more.
            self.relogin()?;
            body = self.post_raw(path, &args)?;
            if is_logout_redirect(&body) {
                return Err(Error::LoggedOut("Die Sitzung ist abgelaufen".into()));
            }
        }
        {
            let mut session = self.session.lock().unwrap();
            if let Some(seconds) = session.config.as_ref().map(|c| c.auto_logout_seconds.max(60) as u64) {
                session.logout_at = Some(Instant::now() + Duration::from_secs(seconds));
            }
        }
        Ok(serde_json::from_str(&body).unwrap_or(Value::String(body)))
    }

    /// A page of the register as text (GET), e.g. the certificate.
    pub fn get_text(&self, path: &str) -> Result<String, Error> {
        if self.demo {
            return Ok(demo::text(path));
        }
        self.ensure_logged_in()?;
        let fetch = || -> Result<String, Error> {
            self.agent
                .get(self.address(path))
                .call()
                .map_err(network_error)?
                .body_mut()
                .read_to_string()
                .map_err(|e| Error::Server(e.to_string()))
        };
        let mut body = fetch()?;
        if is_logout_redirect(&body) {
            self.relogin()?;
            body = fetch()?;
        }
        Ok(body)
    }

    /// Changes the password on the server. Afterwards this connection is
    /// logged out: continue with a new [Client] that has the new password.
    pub fn change_password(&self, new: &str) -> Result<(), Error> {
        if self.demo {
            return Err(Error::Server("In der Demo kann das Passwort nicht geändert werden".into()));
        }
        let mut session = self.session.lock().unwrap();
        self.agent.cookie_jar_lock().clear();
        session.logged_in = false;
        let response: Value = self
            .agent
            .post(self.address("api/auth/setNewPassword"))
            .send_json(json!({ "username": self.user, "oldPassword": self.pass, "newPassword": new }))
            .map_err(network_error)?
            .body_mut()
            .read_json()
            .map_err(|e| Error::Server(e.to_string()))?;
        if response["error"].is_null() {
            Ok(())
        } else {
            Err(Error::Server(format!(
                "[{}] {}",
                response["error"].as_str().unwrap_or("error"),
                response["message"].as_str().unwrap_or_default()
            )))
        }
    }

    /// Downloads a file (GET with query parameters), e.g. an attachment.
    pub fn download(&self, path: &str, query: &[(&str, String)]) -> Result<Vec<u8>, Error> {
        if self.demo {
            return Ok(b"Das ist ein Anhang der Demo.\n".to_vec());
        }
        self.ensure_logged_in()?;
        let mut request = self.agent.get(self.address(path));
        for (key, value) in query {
            request = request.query(key, value);
        }
        let mut response = request.call().map_err(network_error)?;
        if response.status() != 200 {
            return Err(Error::Server(format!("Der Server antwortet mit Fehler {}", response.status().as_u16())));
        }
        response
            .body_mut()
            .with_config()
            .limit(200 * 1024 * 1024)
            .read_to_vec()
            .map_err(|e| Error::Server(e.to_string()))
    }

    /// The semester the server answers for (grades).
    pub fn select_semester(&self, semester: u8) -> Result<(), Error> {
        if self.demo {
            return Ok(());
        }
        self.ensure_logged_in()?;
        self.agent
            .get(format!("{}/v2/?semesterWechsel={semester}", self.url))
            .call()
            .map_err(network_error)?;
        Ok(())
    }
}

fn is_logout_redirect(body: &str) -> bool {
    let b = body.trim_start();
    b.starts_with("<script") && b.contains("window.location") && b.contains("/v2/login")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn urls() {
        assert_eq!(fix_url("fallmerayer.digitalesregister.it/v2/login"), "https://fallmerayer.digitalesregister.it");
        assert_eq!(fix_url("https://x.digitalesregister.it/"), "https://x.digitalesregister.it");
    }

    #[test]
    fn logout_detection() {
        assert!(is_logout_redirect(
            "<script type=\"text/javascript\">\n window.location = \"https://x.digitalesregister.it/v2/login\";\n</script>"
        ));
        assert!(!is_logout_redirect("[]"));
    }

    #[test]
    fn demo_login_and_request() {
        let c = Client::new("https://vinzentinum.digitalesregister.it", "demo-user-6540", "x");
        assert!(c.is_demo());
        assert_eq!(c.login(None).unwrap().full_name, "Max Mustermann");
        let dashboard = c.send("api/student/dashboard/dashboard", json!({ "viewFuture": true })).unwrap();
        assert!(dashboard.is_array());
    }
}
