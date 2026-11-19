# RegQry

A Windows Registry query CLI written in Rust. The command and Cargo package are both named `regqry`.

**Work in progress:** readonly queries now traverse the local live registry, apply field-specific filters, and stream grouped results. Native x64 development tests include a private application hive. The full platform, permission/view/link, terminal, performance, and release acceptance work remains pending; no public release is available yet.

```powershell
cargo run --locked -- --help
cargo run --locked -- --version
```

Use `regqry [QUERY OPTIONS]`, with field-specific filters, repeated conditions, and explicit registry views. Read the [usage guide](docs/usage.md), [matching reference](docs/matching.md), and [compatibility notes](docs/compatibility.md).

The intended release channels are two Windows ZIP downloads and `cargo install regqry`. The support targets are native x64 Windows 10 22H2 / Windows 11, and native ARM64 Windows 11 24H2 or later, using MSVC. These are acceptance targets; see the compatibility notes for the current validation status.

For development, install Rust 1.100.0 with rustfmt and Clippy, the native MSVC C++ build tools, and a Windows SDK. See [CONTRIBUTING](https://github.com/inaku-Gyan/RegQry/blob/main/CONTRIBUTING.md), [testing](docs/testing.md), and [architecture](docs/architecture.md).

Licensed under the [MIT License](LICENSE).
