# RegQry

A Windows Registry query CLI written in Rust. The command and Cargo package are both named `regqry`.

**Work in progress:** the project foundation implements help, version reporting, and query argument validation. Registry traversal and result rendering are being implemented next. A valid query currently reports this limitation and exits with status 2. No public release is available yet.

```powershell
cargo run --locked -- --help
cargo run --locked -- --version
```

The planned query interface is `regqry [QUERY OPTIONS]`, with field-specific filters, repeated conditions, and explicit registry views. Read the [usage guide](docs/usage.md), [matching reference](docs/matching.md), and [compatibility notes](docs/compatibility.md). Query examples in those guides describe the agreed interface; they do not imply the search engine is available in this development build.

The intended release channels are two Windows ZIP downloads and `cargo install regqry`. The support targets are native x64 Windows 10 22H2 / Windows 11, and native ARM64 Windows 11 24H2 or later, using MSVC. These are acceptance targets; see the compatibility notes for the current validation status.

For development, install Rust 1.100.0 with rustfmt and Clippy, the native MSVC C++ build tools, and a Windows SDK. See [CONTRIBUTING](https://github.com/inaku-Gyan/RegQry/blob/main/CONTRIBUTING.md), [testing](docs/testing.md), and [architecture](docs/architecture.md).

Licensed under the [MIT License](LICENSE).
