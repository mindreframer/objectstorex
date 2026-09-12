# EPIC001 Evidence: Deliver Provider-Native Paginated Delimiter Listing

- **Roadmap:** `@meta/@pm/ROADMAP001.md`
- **Spec:** `@meta/@pm/roadmap001/EPIC001-spec.md`
- **Commit:** `[Listing] Add paginated delimiter pages`
- **Validated:** 2026-09-12 CEST
- **Implementation baseline:** `81b055d`

## Delivered

- Added `ObjectStoreX.list_with_delimiter_page/2` with documented types, result shape, defaults, and pre-NIF validation.
- Retained ordinary `ObjectStore` access for existing operations and native `PaginatedListStore` access for S3, Azure, and GCS.
- Added one-request cloud pages using `/`, native `max_keys`, and provider continuation tokens. Wasabi uses the existing S3-compatible path.
- Added deterministic memory/local compatibility pages with a combined lexical object/prefix order and versioned tokens bound to store, prefix, and page size.
- Preserved the existing complete delimiter listing and recursive streaming APIs.
- Added credential-free Rust, memory, and temporary-local tests plus a credential-gated S3-compatible test with optional `TEST_S3_ENDPOINT`.
- Updated ExDoc, README, streaming/configuration guides, and the Unreleased changelog.

## Verification

| Command | Result |
|---|---|
| `OBJECTSTOREX_BUILD=1 mix compile --warnings-as-errors` | Passed |
| `mix format --check-formatted` | Passed |
| `OBJECTSTOREX_BUILD=1 mix test --exclude cloud --exclude skip_ci` | Passed: 348 tests (19 doctests and 329 tests), 4 skipped, 6 excluded |
| `mix docs` | Passed |
| `cargo fmt --check` | Passed |
| `cargo test --locked --all-features` | Passed: 7 tests |
| `cargo clippy --locked --all-targets --all-features -- -D warnings` | Passed |
| `cargo build --release --locked` | Passed |
| `mix hex.build` | Passed; package checksum `500ade05e45df94653b8cff1de454d9cfbd54be5dffed8af210323387b69aace` |
| `bin/qa_check.sh` | Passed: 353 Elixir tests (19 doctests and 334 tests), 5 skipped; 7 Rust tests; Clippy and warning checks passed |
| `git diff --check` | Passed |

## Optional cloud test

`OBJECTSTOREX_BUILD=1 mix test test/integration/paginated_list_cloud_test.exs --include cloud`
reported `0 tests, 1 skipped` because `TEST_S3_BUCKET` was not configured. No cloud request was made. A credentialed S3/Wasabi run remains optional and was not performed.

## Hygiene

- No credentials or continuation-token values are logged or included in the diff.
- Generated docs, package tarballs, build artifacts, and cloud-created objects are not included.
- Version, lockfiles, checksums, packaged `objectstorex-0.2.1/`, generated `doc/`, and release workflows are unchanged.
- The implementation is committed with the roadmap-prescribed title.
