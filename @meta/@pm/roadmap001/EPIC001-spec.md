# EPIC001 Spec: Deliver Provider-Native Paginated Delimiter Listing

- **Roadmap:** `@meta/@pm/ROADMAP001.md`
- **Commit:** `[Listing] Add paginated delimiter pages`

## Purpose

Expose one bounded, resumable page of immediate objects and virtual folders through ObjectStoreX. Cloud providers must use Rust `object_store` 0.14.1 native pagination, including Wasabi through the S3-compatible `AmazonS3` implementation, while memory/local providers provide deterministic compatibility behavior for tests and local development.

## Inputs

- `@meta/@pm/ROADMAP001.md`
- `@meta/@adr/ARD001-update-to-modern-rust.md`
- `native/objectstorex/Cargo.toml`
- `native/objectstorex/Cargo.lock`
- Rust `object_store` 0.14.1 `ObjectStore`, `PaginatedListStore`, `PaginatedListOptions`, and `PaginatedListResult`
- `native/objectstorex/src/builders.rs`
- `native/objectstorex/src/store.rs`
- `native/objectstorex/src/operations.rs`
- `native/objectstorex/src/errors.rs`
- `native/objectstorex/src/atoms.rs`
- `native/objectstorex/src/types.rs`
- `lib/objectstorex.ex`
- `lib/objectstorex/native.ex`
- `test/list_test.exs`
- `test/obx005_2a_native_configuration_test.exs`
- `README.md`
- `guides/configuration.md`
- `guides/streaming.md`
- `CHANGELOG.md`
- `bin/qa_check.sh`

## Public Elixir contract

Add:

```elixir
@spec list_with_delimiter_page(store(), keyword()) ::
        {:ok,
         %{
           objects: [metadata()],
           prefixes: [String.t()],
           next_page_token: String.t() | nil
         }}
        | {:error, term()}

def list_with_delimiter_page(store, opts \\ [])
```

Example:

```elixir
{:ok, first} =
  ObjectStoreX.list_with_delimiter_page(store,
    prefix: "audio/",
    max_keys: 100
  )

{:ok, second} =
  ObjectStoreX.list_with_delimiter_page(store,
    prefix: "audio/",
    max_keys: 100,
    page_token: first.next_page_token
  )
```

Accepted options:

- `:prefix` — `nil` or a binary; defaults to `nil` for bucket root and follows the existing path-segment behavior of `list_with_delimiter/2`;
- `:max_keys` — integer from 1 through 1,000; defaults to 1,000 and limits objects plus prefixes together;
- `:page_token` — `nil` or a non-empty binary returned by the immediately preceding compatible request; defaults to `nil`.

Unknown options and invalid values return `{:error, {:invalid_option, option_name}}` before invoking native code. A successful terminal page has `next_page_token: nil`. Empty pages are successful and contain empty `objects` and `prefixes` lists.

Page tokens are opaque. Callers must not inspect, alter, persist as durable object identities, or reuse them with a different store, prefix, or option set. A paginated listing is not a point-in-time snapshot; concurrent writes or deletes may affect subsequent pages.

## Compatibility contract

The following existing behavior is frozen:

```elixir
ObjectStoreX.list_with_delimiter(store, opts)
# => {:ok, objects, prefixes}

ObjectStoreX.Stream.list_stream(store, opts)
# => recursive lazy Elixir stream
```

Do not change either function’s name, options, return shape, recursion, metadata map, or error behavior. The new function is additive.

## Rust architecture

`StoreWrapper` retains:

1. `Arc<DynObjectStore>` for all existing provider-neutral operations;
2. an optional `Arc<dyn PaginatedListStore>` for providers that implement native page requests;
3. enough internal provider/capability information to select native or compatibility paging without exposing provider internals to Elixir.

Builder behavior:

| ObjectStoreX provider | Page implementation |
|---|---|
| `:s3` | Native `AmazonS3: PaginatedListStore`; includes Wasabi and other S3-compatible endpoints |
| `:azure` | Native `MicrosoftAzure: PaginatedListStore` |
| `:gcs` | Native `GoogleCloudStorage: PaginatedListStore` |
| `:memory` | Deterministic compatibility pager |
| `:local` | Deterministic compatibility pager |

The cloud path calls `PaginatedListStore::list_paginated` exactly once per ObjectStoreX page request with:

- normalized prefix preserving existing segment semantics;
- delimiter `/`;
- `max_keys` from the validated Elixir option;
- the caller’s opaque `page_token`;
- no offset and default extensions.

Encode `PaginatedListResult.result.objects`, `result.common_prefixes`, and `page_token` into the public result. Reuse the existing metadata encoding and provider-error mapping. Do not log options, provider request headers, credentials, or native tokens.

The native NIF declaration must be covered by the existing export inventory test. It must execute on a dirty scheduler and must not perform cloud network work on a normal BEAM scheduler.

## Memory/local compatibility pager

Because Rust `object_store` 0.14.1 does not implement `PaginatedListStore` for memory/local:

1. call the existing complete delimiter listing for the selected prefix;
2. represent each immediate object and common prefix as one internal entry;
3. sort the combined entries lexically by path with an explicit deterministic tie-breaker for object versus prefix;
4. validate and resume from a versioned ObjectStoreX-owned opaque token bound to the compatibility pager and selected prefix;
5. take at most `max_keys` combined entries;
6. split those entries into the returned `objects` and `prefixes` collections;
7. return another token only when entries remain.

Malformed or mismatched ObjectStoreX fallback tokens return `{:error, :invalid_page_token}`. The token contains no credentials or local filesystem root. Documentation must state that this fallback materializes one complete immediate level and therefore provides semantic parity, not provider-bounded I/O.

## Behavioral requirements

- `max_keys` counts objects and prefixes together.
- Exact-boundary pages terminate with `nil`; do not return an empty trailing page token.
- A page size of one works for objects, prefixes, and mixed listings.
- Nested descendants appear only through their immediate common prefix.
- Directory marker objects retain the underlying `object_store` semantics; do not invent additional filtering in this library feature.
- Native result ordering is provider-defined. Do not sort individual native pages in a way that invalidates provider continuation tokens.
- For an unchanged memory/local listing, following tokens to termination yields every immediate entry exactly once, without gaps or duplicates.
- Provider errors continue through `ObjectStoreX.Error` conventions; no cloud-specific exception escapes the NIF.

## Testing

### Credential-free Elixir tests

Use `ObjectStoreX.new(:memory)` and a temporary local provider to cover:

- root and nested prefixes;
- mixed immediate objects and common prefixes;
- page sizes 1, 2, 3, and 1,000;
- empty, partial, exact-boundary, and terminal pages;
- repeated token traversal collecting all entries exactly once;
- malformed options and fallback tokens;
- deterministic memory/local parity;
- unchanged `list_with_delimiter/2` and `Stream.list_stream/2` behavior;
- the new native function export.

### Rust tests

Cover:

- native capability registration for S3, Azure, and GCS builders;
- compatibility capability registration for memory/local builders;
- option translation to `PaginatedListOptions`;
- combined object/prefix slicing and tie-breaking;
- fallback token encode/decode, prefix binding, invalid version, and terminal detection;
- result encoding with nullable next token;
- provider error mapping.

### Optional S3-compatible test

Add a test tagged `:cloud` that runs only when the established S3 test credentials are available. Accept optional `TEST_S3_ENDPOINT` so the same test can target Wasabi or another S3-compatible service. It must:

- write objects beneath a unique temporary prefix;
- force multiple pages with a small `max_keys`;
- verify native tokens reach every expected immediate object/prefix exactly once;
- remove every test object in `on_exit`/`after` cleanup;
- never print credentials or token values.

Credential absence skips this test and does not weaken the required memory/local/Rust gate.

## Documentation

Update:

- `README.md` with a short bounded folder-listing example and provider matrix;
- `guides/streaming.md` to distinguish recursive streaming, complete delimiter listing, and bounded delimiter pages;
- `guides/configuration.md` to name Wasabi as S3-compatible and document optional `TEST_S3_ENDPOINT` for the cloud smoke test;
- `CHANGELOG.md` under Unreleased with the additive public API and native/fallback provider behavior;
- ExDoc on `ObjectStoreX.list_with_delimiter_page/2` with option, token, ordering, consistency, and fallback caveats.

## Exact implementation paths

Planning and evidence:

- `@meta/@pm/ROADMAP001.md`
- `@meta/@pm/roadmap001/EPIC001-spec.md`
- `@meta/@pm/roadmap001/EPIC001-plan.md`
- `@meta/@pm/roadmap001/evidence/EPIC001.md`

Native implementation:

- `native/objectstorex/src/store.rs`
- `native/objectstorex/src/builders.rs`
- `native/objectstorex/src/operations.rs`
- `native/objectstorex/src/types.rs`
- `native/objectstorex/src/atoms.rs`
- `native/objectstorex/src/errors.rs` only if an existing provider error cannot be represented correctly

Elixir implementation:

- `lib/objectstorex/native.ex`
- `lib/objectstorex.ex`

Tests:

- `test/list_test.exs`
- `test/obx005_2a_native_configuration_test.exs`
- `test/integration/paginated_list_cloud_test.exs`
- Rust unit-test modules colocated with the changed native source files

Documentation:

- `README.md`
- `guides/configuration.md`
- `guides/streaming.md`
- `CHANGELOG.md`

Do not edit generated `doc/`, packaged `objectstorex-0.2.1/`, release tarballs, checksums, package version, lockfiles, or NIF release workflows in this implementation epic.

## Verification

Run focused tests while implementing, then run the complete gate from the repository root:

```bash
OBJECTSTOREX_BUILD=1 mix compile --warnings-as-errors
mix format --check-formatted
mix test --exclude cloud --exclude skip_ci
mix docs

cd native/objectstorex
cargo fmt --check
cargo test --locked --all-features
cargo clippy --locked --all-targets --all-features -- -D warnings
cargo build --release --locked
cd ../..

mix hex.build
bin/qa_check.sh
git diff --check
```

If credentials are intentionally supplied, also run the optional S3-compatible test separately. Never make it part of the credential-free acceptance gate.

## Acceptance

- The Elixir operation returns bounded mixed folder/object pages and an opaque next token.
- Wasabi/S3, Azure, and GCS invoke one native Rust page request per call rather than draining the complete level.
- Memory/local behavior is deterministic, fully tested, and honestly documented as materializing fallback behavior.
- Existing list APIs remain source- and behavior-compatible.
- Invalid input cannot panic the NIF or leak provider internals.
- Complete traversal works across small page sizes without gaps, duplicates, or unnecessary terminal tokens for an unchanged listing.
- Documentation clearly tells callers when to use streaming, complete delimiter listing, or paginated delimiter listing.
- Every required quality command passes and evidence records the results.
