# Changelog

Version entries are reviewed before their release tags. See [GitHub Releases](https://github.com/inaku-Gyan/RegQry/releases) and [crates.io](https://crates.io/crates/regqry) for publication availability.

## Unreleased

## [0.1.2] - 2026-11-20

Initial read-only registry search candidate: multiple roots and views, field-specific regex/glob/data/type/time filters, grouped UTF-8 previews, cancellation and explicit incomplete-query status. Full query features and limitations are listed under 0.1.0.

### Fixed

- Read every page of GitHub job/artifact metadata using compatible gh arguments and the existing JSON decoder. Empty, single-item and multiple-page responses retain their actual meaning; malformed data remains unknown.
- Retry missing readback after successful draft creation, with bounded reads and no repeated creation/upload. Read errors still stop the release.
- Check the real gh client against read-only workflow metadata in CI, in addition to synthetic recovery tests.

### Release status

- The v0.1.1 candidate remains frozen and unchanged after input export failed; it never reached source acceptance, Cargo upload or public GitHub publication. Corrected code uses a new tag/version.
- Executables are unsigned. Automated acceptance uses native hosted x64 Windows Server and ARM64 Windows 11; minimum/clean clients and human terminal/physical-keyboard checks remain deferred. See the [compatibility notes](docs/compatibility.md).

## [0.1.1] - 2026-11-20

First publication candidate, containing the initial read-only registry search features described under 0.1.0.

### Fixed

- Allow the GitHub Actions installation token to pass release preparation by checking actual Contents write capability without creating or changing a Release. Repository `permissions.push` can be false for a correctly scoped installation token.

### Release status

- The `v0.1.0` attempt stopped at Inspect before any candidate, Cargo upload or GitHub Release was created. Its tag remains unchanged; the corrected release uses a new version.

## [0.1.0] - 2026-11-20

Initial read-only Windows Registry query CLI, using the command and Cargo package name `regqry`.

### Added

- Direct `regqry [QUERY OPTIONS]` searches, short/full help and version output. No arguments display help without querying the registry.
- Multiple arbitrary search roots, relative key-path matching and explicit 32/64-bit views. Defaults search descendants of HKCU and HKLM in all supported views.
- Field-specific regex/glob filters for keys, value names and data; raw hexadecimal and empty/missing-data conditions; value-type inclusion/exclusion and key modification-time bounds. Repeated conditions within a field use OR; field groups use AND, with type exclusions applied globally.
- Explicit environment-expanded matching for REG_EXPAND_SZ, based on one process-environment snapshot. Saved bytes remain unchanged.
- Lossless native reads and grouped UTF-8 results containing full key/value identities, type information, raw byte counts and clearly marked data previews. Missing default values, empty data and malformed saved representations remain distinct.
- Streaming execution, Ctrl+C cancellation and partial-failure diagnostics. Exit codes are 0 for complete matches, 1 for complete zero matches, 2 for invalid input/incomplete execution and 130 for cancellation.
- Native x64/ARM64 Windows MSVC ZIP distribution and Windows-only Cargo installation through the versioned release workflow. Packages include license materials; releases include SHA-256 checksums and original acceptance records.

### Limitations

- Queries are read-only and use the live registry without a consistent snapshot or guaranteed ordering. A search root's own key and values are excluded. Editing, TUI interaction and additional output formats are deferred.
- Executables are unsigned. Compatibility targets are x64 Windows 10 22H2 / Windows 11 and ARM64 Windows 11 24H2 or later. Automated acceptance uses GitHub-hosted native x64 Windows Server and ARM64 Windows 11; minimum/clean clients, visible terminal layout and physical-keyboard checks remain unexecuted and deferred. See the [compatibility notes](docs/compatibility.md) and [validation records](https://github.com/inaku-Gyan/RegQry/blob/main/docs/validation/README.md).
