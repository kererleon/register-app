//! Attachments of messages: kept in the downloads folder and opened with
//! the system's program for the file.

use std::path::{Path, PathBuf};

use crate::settings;

/// Where the attachment [name] is kept.
pub fn path(name: &str) -> PathBuf {
    #[cfg(not(any(target_os = "android", target_os = "ios")))]
    let dir = directories::UserDirs::new().and_then(|d| d.download_dir().map(Path::to_owned));
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let dir: Option<PathBuf> = None;
    dir.unwrap_or_else(|| settings::dir().join("attachments")).join(name)
}

/// Writes the file; a failed download leaves nothing behind.
pub fn save(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir)?;
    }
    std::fs::write(path, bytes).inspect_err(|_| {
        let _ = std::fs::remove_file(path);
    })
}

/// Opens the file with the program the system uses for it.
pub fn open(path: &Path) {
    // Never started through a shell: the name comes from the server.
    #[cfg(target_os = "macos")]
    let _ = std::process::Command::new("open").arg(path).spawn();
    #[cfg(target_os = "windows")]
    let _ = std::process::Command::new("explorer").arg(path).spawn();
    #[cfg(all(unix, not(any(target_os = "macos", target_os = "android", target_os = "ios"))))]
    let _ = std::process::Command::new("xdg-open").arg(path).spawn();
    #[cfg(any(target_os = "android", target_os = "ios"))]
    let _ = path;
}
