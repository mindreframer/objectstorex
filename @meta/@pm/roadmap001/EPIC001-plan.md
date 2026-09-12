# EPIC001 Plan: Deliver Provider-Native Paginated Delimiter Listing

- **Spec:** `@meta/@pm/roadmap001/EPIC001-spec.md`
- **Commit:** `[Listing] Add paginated delimiter pages`
- **Execution:** Complete phases in order. Do not mark a phase or gate complete until its stated checks pass.

## Progress

- [x] **Phase 1.1 — Freeze the additive public contract**
  - Add failing Elixir tests for `list_with_delimiter_page/2`, its result map, defaults, accepted options, combined `max_keys`, opaque token traversal, terminal `nil`, and malformed-option errors.
  - Extend the native export inventory test for the new NIF declaration.
  - Add compatibility assertions proving the existing complete and streaming list APIs retain their current shapes.

- [x] **Phase 1.2 — Retain provider pagination capability in Rust**
  - Extend `StoreWrapper` without replacing its existing `Arc<DynObjectStore>`.
  - Retain `Arc<dyn PaginatedListStore>` for S3, Azure, and GCS builders.
  - Select the compatibility pager for memory/local providers.
  - Add Rust tests for provider-capability registration without making cloud requests.

- [x] **Phase 1.3 — Implement one native/fallback page operation**
  - Add the dirty-scheduled Rustler NIF and translate validated prefix, `/` delimiter, `max_keys`, and `page_token` into one `PaginatedListOptions` request.
  - Encode objects, prefixes, and nullable next token with the existing metadata/error conventions.
  - Implement deterministic combined-entry paging and versioned prefix-bound tokens for memory/local.
  - Add Rust tests for page boundaries, token validation, tie-breaking, terminal detection, and errors.

- [x] **Phase 1.4 — Expose the safe Elixir API**
  - Declare the NIF in `ObjectStoreX.Native`.
  - Add types, option validation, ExDoc, examples, and the public wrapper in `ObjectStoreX`.
  - Reject malformed/unknown options before native execution.
  - Keep `list_with_delimiter/2` and `ObjectStoreX.Stream.list_stream/2` unchanged.

- [x] **Phase 1.5 — Prove provider-neutral behavior without credentials**
  - Complete memory tests covering root, prefix, empty, mixed, nested, page-size-one, partial, exact-boundary, and multi-page traversal cases.
  - Add equivalent temporary-local-provider traversal coverage.
  - Prove combined page limits, deterministic fallback parity, invalid token handling, and no gaps/duplicates over unchanged listings.
  - Run all focused Rust and Elixir listing tests with source NIF compilation.

- [x] **Phase 1.6 — Add optional S3-compatible verification and documentation**
  - Add a credential-gated `:cloud` integration test using a unique prefix, small pages, guaranteed cleanup, and optional `TEST_S3_ENDPOINT` for Wasabi.
  - Update README, streaming/configuration guides, ExDoc, and Unreleased changelog.
  - Document native S3/Wasabi/Azure/GCS paging, memory/local materialization, opaque-token reuse rules, provider ordering, and non-snapshot consistency.
  - Confirm no credential, token value, generated object, or cloud test artifact is committed.

- [x] **Phase 1.7 — Complete cumulative quality and package verification**
  - Run source compile, Elixir format/tests/docs, locked Rust format/tests/Clippy/release build, `mix hex.build`, `bin/qa_check.sh`, and `git diff --check`.
  - Run the optional Wasabi/S3-compatible test only when credentials are intentionally available; record it separately from the required gate.
  - Record exact results in `@meta/@pm/roadmap001/evidence/EPIC001.md`.
  - Review the staged diff against the roadmap’s exact paths and commit only this epic as `[Listing] Add paginated delimiter pages`.

## Quality Gate

- [x] The new operation is additive and all legacy list contracts remain unchanged.
- [x] Elixir option validation covers unknown keys, prefix, `max_keys`, and `page_token` without NIF panics.
- [x] Native cloud providers perform one `PaginatedListStore::list_paginated` request per public page call.
- [x] Wasabi is supported through the ordinary S3-compatible endpoint path without provider-specific protocol code.
- [x] Memory/local compatibility pages are deterministic and explicitly documented as full-level materialization.
- [x] `max_keys` bounds objects and prefixes together for empty, partial, full, and exact-boundary pages.
- [x] Following tokens over an unchanged listing returns every immediate entry exactly once and terminates with `nil`.
- [x] Invalid fallback tokens and provider errors return through documented ObjectStoreX error shapes.
- [x] Existing `list_with_delimiter/2` and `ObjectStoreX.Stream.list_stream/2` tests pass unchanged.
- [x] Credential-free tests never contact S3, Wasabi, Azure, GCS, or another external service.
- [x] Optional cloud coverage uses a unique prefix, cleans up in failure paths, and does not print secrets/tokens.
- [x] `OBJECTSTOREX_BUILD=1 mix compile --warnings-as-errors` passes.
- [x] `mix format --check-formatted`, credential-free `mix test`, and `mix docs` pass.
- [x] `cargo fmt --check`, locked all-feature tests, strict Clippy, and locked release build pass.
- [x] `mix hex.build`, `bin/qa_check.sh`, and `git diff --check` pass.
- [x] Package contents include the changed native and Elixir sources but no generated docs, credentials, or transient artifacts.
- [x] Evidence is complete and the epic commit title is exactly `[Listing] Add paginated delimiter pages`.
