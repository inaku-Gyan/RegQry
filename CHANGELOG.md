# Changelog

User-facing changes are reviewed here before creating a release tag. This project has not published a release.

## Unreleased

### Added

- Windows-only Rust project foundation, fixed toolchain, query argument validation, and development checks.
- Local readonly registry queries with relative multi-root filters, regex/glob/data/type/time conditions, explicit views, streaming grouped previews, cancellation and incomplete-search diagnostics.
- Constructed query/error tests and a private application-hive test for lossless native reads, long names, large values and unknown types.
- Native static-CRT development test bundles with file identities, DLL inspection, Cargo-free relocation checks and controlled rejection probes.
- An opt-in disposable-VM suite for real roots, physical registry views, minimum permissions and registry links, with separate setup/query tokens and preserved rollback requirements.
- Native private-hive checks for changing/deleted values, retry exhaustion, malformed UTF-16 names and saved data; real closed-pipe write/flush checks in the query/output path.
- Isolated console/process-control probes and opt-in VM cases for actual CLI streaming, Ctrl+C, closed stdout pipes, long values and first-result/working-set measurements.
- Actual cmd/Windows PowerShell 5.1/PowerShell 7 invocation and encoding checks, with separate owned-VM query cases and a manual terminal acceptance record template.

### Fixed

- Grow registry name buffers independently of failed enumeration output, and observe cancellation before allocating a larger retry buffer.
