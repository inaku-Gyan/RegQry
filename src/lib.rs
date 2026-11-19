//! Application assembly for the regqry binary; no stable Rust library API is promised.

#[cfg(not(windows))]
compile_error!("RegQry supports Windows only. Use a native Windows MSVC toolchain.");

#[cfg(windows)]
mod cli;
#[cfg(windows)]
mod output;
#[cfg(windows)]
mod query;
#[cfg(windows)]
mod registry;
#[cfg(windows)]
mod value;

/// Run the command-line application.
#[cfg(windows)]
pub fn run() -> std::process::ExitCode {
    cli::run()
}
