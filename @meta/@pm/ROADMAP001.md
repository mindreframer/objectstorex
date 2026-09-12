# ROADMAP001 — Add bounded delimiter-aware listing pages

- **Status:** Accepted — implementation not started
- **Created:** 2026-09-12
- **Baseline commit:** `a8c5904`
- **Scope:** Expose bounded, resumable folder listings through ObjectStoreX without replacing the existing complete or streaming list APIs
- **Planning commit:** `[Roadmap] Plan paginated delimiter listing`
- **Implementation commit:** `[Listing] Add paginated delimiter pages`

## Goal

Add a provider-neutral Elixir API that returns one bounded page of immediate objects and virtual folders plus an opaque continuation token. S3-compatible services such as Wasabi must use the native `ListObjectsV2` pagination already supplied by Rust `object_store`; ObjectStoreX must not reimplement an S3 client in Elixir.

## Verified technical baseline

1. `native/objectstorex/Cargo.toml` depends on `object_store` 0.14.1.
2. `object_store::list::PaginatedListStore` is public and accepts `prefix`, `delimiter`, `max_keys`, `page_token`, and `offset` through `PaginatedListOptions`.
3. `AmazonS3`, `MicrosoftAzure`, and `GoogleCloudStorage` implement `PaginatedListStore`. The S3 implementation maps directly to `ListObjectsV2`, including `continuation-token`, `delimiter`, `max-keys`, `prefix`, and `start-after`; this also applies to Wasabi through its S3-compatible endpoint.
4. The higher-level `ObjectStore::list_with_delimiter` drains every provider page and returns one combined `ListResult` without the final provider token.
5. ObjectStoreX currently stores only `Arc<DynObjectStore>` in `StoreWrapper`, calls that complete-list method, and returns `{:ok, objects, prefixes}`. The provider’s paginated capability is therefore erased at the current Rustler boundary.
6. Rust `object_store` does not implement `PaginatedListStore` for the in-memory or local-filesystem providers, so ObjectStoreX needs a documented deterministic fallback if the public API is to remain testable and provider-neutral.

## Fixed decisions

1. Add one new public function and preserve the existing APIs unchanged:

   ```elixir
   ObjectStoreX.list_with_delimiter_page(store,
     prefix: "audio/",
     max_keys: 100,
     page_token: previous_token
   )
   ```

2. Return:

   ```elixir
   {:ok,
    %{
      objects: [ObjectStoreX.metadata()],
      prefixes: [String.t()],
      next_page_token: String.t() | nil
    }}
   ```

3. `:prefix` defaults to bucket root and keeps the same path-segment semantics as `list_with_delimiter/2`. The delimiter remains `/`; this roadmap does not expose arbitrary delimiters.
4. `:max_keys` defaults to `1_000` and must be an integer from 1 through 1,000. It limits objects and common prefixes together, matching S3 `MaxKeys` behavior.
5. `:page_token` defaults to `nil`; otherwise it must be a non-empty binary. It is opaque and must be passed back unchanged with the same store, prefix, and listing options.
6. Reject unknown or malformed options before entering the NIF with `{:error, {:invalid_option, option_name}}`.
7. Preserve both capabilities in the Rust resource: the ordinary `ObjectStore` trait for all existing operations and an optional native `PaginatedListStore` trait object for S3, Azure, and GCS.
8. S3, including Wasabi and other compatible endpoints, Azure, and GCS use the Rust crate’s native page request and native provider token. No cloud listing is materialized or sliced in Elixir.
9. Memory and local providers use a Rust-side compatibility pager over `list_with_delimiter`: combine immediate objects and prefixes in deterministic lexical path order, resume from an ObjectStoreX-owned opaque versioned token, return at most `max_keys` entries, and split the page back into objects and prefixes.
10. Documentation must explicitly state that memory/local fallback pagination preserves API semantics but materializes the complete immediate level internally; only S3/Azure/GCS provide provider-bounded I/O.
11. A sequence of pages over an unchanged listing must return every immediate object/prefix exactly once and terminate with `next_page_token: nil`. Listings are not snapshots; concurrent object mutation may change subsequent pages.
12. Existing `ObjectStoreX.list_with_delimiter/2` continues returning the complete `{:ok, objects, prefixes}` tuple. Existing `ObjectStoreX.Stream.list_stream/2` remains the recursive lazy-list API.
13. The NIF encodes provider errors through the existing ObjectStoreX error boundary and must never expose credentials, signed URLs, or request headers in page tokens, errors, logs, or tests.
14. Normal automated tests use memory/local storage. A credential-gated `:cloud` test may validate S3-compatible pagination with an optional custom endpoint, unique temporary prefix, and cleanup; it is excluded from the required credential-free gate.
15. This roadmap delivers source and package readiness only. Version bumping, GitHub release creation, precompiled NIF publication, checksum generation, Hex publication, and downstream Moo Courses adoption require separate explicit release/adoption work.

## Implementation

One vertical epic is sufficient because the public contract, retained Rust capability, NIF encoding, fallback semantics, tests, and documentation form one backwards-compatible listing operation:

1. **EPIC001 — Deliver provider-native paginated delimiter listing**
   - Define the Elixir contract and compatibility behavior.
   - Retain and call Rust `PaginatedListStore` for cloud providers.
   - Implement deterministic memory/local compatibility pages.
   - Add complete Rust, Elixir, optional S3-compatible, documentation, and package verification.

Detailed files:

- `roadmap001/EPIC001-spec.md`
- `roadmap001/EPIC001-plan.md`

## Testing strategy

- Elixir public-contract tests prove option validation, result shape, opaque token round trips, terminal pages, and unchanged legacy APIs.
- Memory and local tests use mixed immediate objects and virtual folders, page sizes of 1–3, nested descendants, empty prefixes, exact-boundary pages, and invalid tokens.
- Rust tests prove native-capability selection for S3/Azure/GCS, fallback selection for memory/local, combined object/prefix limits, deterministic continuation, encoding, and provider-error propagation.
- An optional credentialed S3-compatible test accepts an endpoint so Wasabi can verify multiple native pages without making live storage part of the standard test gate.
- Source builds, locked Rust tests, Clippy, formatting, Elixir tests, docs, package contents, and the repository QA script form the cumulative gate.

## Definition of complete

- [ ] `list_with_delimiter_page/2` has a documented, typed, backwards-compatible Elixir contract.
- [ ] S3/Wasabi, Azure, and GCS use `PaginatedListStore` with native `max_keys` and page tokens.
- [ ] Memory and local providers have deterministic compatibility pagination with the documented materialization caveat.
- [ ] Mixed object/prefix pages are bounded by one combined `max_keys` limit and terminate correctly.
- [ ] Invalid options/tokens and provider failures return stable errors without leaking sensitive provider context.
- [ ] Existing complete delimiter listing and recursive streaming listing behavior remain unchanged.
- [ ] Credential-free Rust and Elixir coverage passes; optional S3-compatible coverage is documented and safe.
- [ ] README, ExDoc guides, and changelog explain provider support, Wasabi compatibility, token rules, and consistency limitations.
- [ ] Source/release builds and Hex package-content checks pass without relying on an old precompiled NIF.
- [ ] `bin/qa_check.sh` and the complete explicit quality gate pass.
- [ ] EPIC001 evidence is recorded and committed with `[Listing] Add paginated delimiter pages`.

## Out of scope

Recursive page APIs, arbitrary delimiters, automatic prefetching, client-side token decoding, snapshot isolation across bucket mutations, sorting guarantees for native cloud providers beyond their documented behavior, provider-specific Elixir APIs, changing existing list return shapes, object mutation APIs, a new S3 protocol client, dependency upgrades, package version bumps, release tags, precompiled artifact publication, Hex publication, and downstream application UI/API changes.
