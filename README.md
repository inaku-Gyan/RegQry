# RegQry

A Windows Registry query CLI written in Rust. Find keys and values using field-specific filters, then inspect their types and data previews. Queries are read-only and stream results as they are found.

The command and Cargo package are both named `regqry`. See [Releases](https://github.com/inaku-Gyan/RegQry/releases) for available versions and the [validation status](https://github.com/inaku-Gyan/RegQry/blob/main/docs/validation/README.md) for executed checks. Version notes are prepared before publication.

```powershell
regqry --key-root 'HKCU\Software' --key 'terminal'
regqry --name '^InstallPath$' --data-i 'vendor'
regqry --key-root 'HKLM\Software' --type dword --view 64
```

Use `regqry [QUERY OPTIONS]`. No arguments or `-h` displays short help; `--help` displays the full reference. Repeated conditions within a field are alternatives; conditions across fields must all match, and type exclusions apply to every candidate. Read the [usage guide](docs/usage.md), [matching reference](docs/matching.md), and [compatibility notes](docs/compatibility.md).

## Installation

For a published version, download the Windows ZIP matching your native architecture from [Releases](https://github.com/inaku-Gyan/RegQry/releases): `x86_64-pc-windows-msvc` or `aarch64-pc-windows-msvc`. Extract the complete directory and run `regqry.exe --help`. Add that directory to PATH if desired. The executable is unsigned. Releases include SHA-256 checksums; ZIPs carry [third-party distribution materials](docs/distribution.md).

Alternatively, install the published Cargo package on Windows:

```powershell
cargo install regqry --version 0.1.0 --locked
```

Cargo installation requires Rust 1.100.0 or a newer accepted compiler, native MSVC C++ build tools, and a Windows SDK. Only Rust 1.100.0 is tested. Non-Windows compilation is deliberately rejected.

Compatibility targets are native x64 Windows 10 22H2 / Windows 11 and native ARM64 Windows 11 24H2 or later. Actual automated checks run on GitHub-hosted native x64 Windows Server and ARM64 Windows 11. Minimum/clean clients, visible terminal layout and physical-keyboard Ctrl+C remain unexecuted and deferred; the compatibility notes distinguish these targets from actual evidence.

## Query behavior

Defaults search descendants of HKCU and HKLM in all supported registry views. Explicit `--key-root` options replace those roots; a root's own key and values are excluded. Key/name/data/type/time filters narrow results without pruning descendant traversal. Name/data/type conditions select values; root/key/time/view conditions alone return keys.

Results use grouped UTF-8 text with complete target identities and marked data previews. Complete matches exit 0, complete zero matches exit 1 with empty output, incomplete queries or invalid input exit 2, and cancellation exits 130. Registry reads are live and do not form a consistent snapshot. Editing, TUI interaction and additional output formats are outside this version.

## Development

For development, install Rust 1.100.0 with rustfmt and Clippy, the native MSVC C++ build tools, and a Windows SDK. See [CONTRIBUTING](https://github.com/inaku-Gyan/RegQry/blob/main/CONTRIBUTING.md), [testing](docs/testing.md), and [architecture](docs/architecture.md).

```powershell
cargo run --locked -- --help
./scripts/check.ps1
```

Licensed under the [MIT License](LICENSE).
