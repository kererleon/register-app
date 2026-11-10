fn main() {
    slint_build::compile_with_config(
        "ui/app.slint",
        slint_build::CompilerConfiguration::new().with_style("fluent-dark".into()),
    )
    .expect("Slint UI");

    // The icon of Register-Rust.exe.
    #[cfg(windows)]
    {
        let mut res = winresource::WindowsResource::new();
        res.set_icon("windows/icon.ico");
        res.set("ProductName", "Register Rust");
        res.set("FileDescription", "Register – Rust-Version");
        res.compile().expect("Windows resources");
    }
}
