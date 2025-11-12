use crate::atoms;
use crate::errors::map_error;
use crate::store::StoreWrapper;
use crate::RUNTIME;
use object_store::{path::Path, PutPayload};
use rustler::{Binary, Encoder, Env, NifResult, OwnedBinary, ResourceArc, Term};

/// Upload an object to storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn put<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    data: Binary,
) -> NifResult<Term<'a>> {
    let payload = PutPayload::from(data.as_slice().to_vec());

    match RUNTIME.block_on(async { store.inner.put(&Path::from(path), payload).await }) {
        Ok(_) => Ok(atoms::ok().to_term(env)),
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Download an object from storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn get<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    let result = RUNTIME.block_on(async { store.inner.get(&Path::from(path)).await });

    match result {
        Ok(get_result) => match RUNTIME.block_on(async { get_result.bytes().await }) {
            Ok(bytes) => {
                let mut binary = OwnedBinary::new(bytes.len()).unwrap();
                binary.as_mut_slice().copy_from_slice(&bytes);
                Ok(binary.release(env).to_term(env))
            }
            Err(e) => Ok(map_error(e).to_term(env)),
        },
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Delete an object from storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn delete<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    match RUNTIME.block_on(async { store.inner.delete(&Path::from(path)).await }) {
        Ok(_) => Ok(atoms::ok().to_term(env)),
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Get object metadata without downloading content
#[rustler::nif(schedule = "DirtyCpu")]
pub fn head<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    let meta = RUNTIME.block_on(async { store.inner.head(&Path::from(path)).await });

    match meta {
        Ok(meta) => {
            // Convert ObjectMeta to Elixir map
            let map = rustler::types::map::map_new(env);
            let map = map
                .map_put(
                    rustler::types::atom::Atom::from_str(env, "location")
                        .unwrap()
                        .to_term(env),
                    meta.location.to_string().encode(env),
                )
                .ok()
                .unwrap();
            let map = map
                .map_put(
                    rustler::types::atom::Atom::from_str(env, "size")
                        .unwrap()
                        .to_term(env),
                    meta.size.encode(env),
                )
                .ok()
                .unwrap();
            let map = map
                .map_put(
                    rustler::types::atom::Atom::from_str(env, "last_modified")
                        .unwrap()
                        .to_term(env),
                    meta.last_modified.to_string().encode(env),
                )
                .ok()
                .unwrap();

            if let Some(etag) = meta.e_tag {
                let map = map
                    .map_put(
                        rustler::types::atom::Atom::from_str(env, "etag")
                            .unwrap()
                            .to_term(env),
                        etag.encode(env),
                    )
                    .ok()
                    .unwrap();
                Ok(map)
            } else {
                Ok(map)
            }
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Copy an object within storage (server-side)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn copy<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Term<'a>> {
    match RUNTIME.block_on(async { store.inner.copy(&Path::from(from), &Path::from(to)).await }) {
        Ok(_) => Ok(atoms::ok().to_term(env)),
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Rename an object (server-side move)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn rename<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Term<'a>> {
    match RUNTIME.block_on(async { store.inner.rename(&Path::from(from), &Path::from(to)).await }) {
        Ok(_) => Ok(atoms::ok().to_term(env)),
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Fetch multiple byte ranges from an object in a single operation
#[rustler::nif(schedule = "DirtyCpu")]
pub fn get_ranges<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    ranges: Vec<(u64, u64)>,
) -> NifResult<Term<'a>> {
    use std::ops::Range;

    // Convert Vec<(u64, u64)> to Vec<Range<usize>>
    let range_objects: Vec<Range<usize>> = ranges
        .into_iter()
        .map(|(start, end)| (start as usize)..(end as usize))
        .collect();

    let results = RUNTIME.block_on(async {
        store
            .inner
            .get_ranges(&Path::from(path), &range_objects)
            .await
    });

    match results {
        Ok(bytes_vec) => {
            // Convert Vec<Bytes> to Vec<Binary> for Elixir
            let binaries: Vec<Term> = bytes_vec
                .into_iter()
                .map(|bytes| {
                    let mut binary = OwnedBinary::new(bytes.len()).unwrap();
                    binary.as_mut_slice().copy_from_slice(&bytes);
                    binary.release(env).encode(env)
                })
                .collect();

            Ok(binaries.encode(env))
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Delete multiple objects in bulk with automatic batching
#[rustler::nif(schedule = "DirtyCpu")]
pub fn delete_many<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    paths: Vec<String>,
) -> NifResult<Term<'a>> {
    use futures::stream::{self, StreamExt};

    // Create a stream of paths
    let path_stream = stream::iter(paths.into_iter().map(|p| Ok(Path::from(p)))).boxed();

    // Call delete_stream to delete all objects
    let delete_stream = store.inner.delete_stream(path_stream);

    // Collect results
    let results = RUNTIME.block_on(async { delete_stream.collect::<Vec<_>>().await });

    // Count successes and collect failures
    let mut succeeded = 0usize;
    let mut failed = Vec::new();

    for (idx, result) in results.into_iter().enumerate() {
        match result {
            Ok(_) => succeeded += 1,
            Err(e) => failed.push((idx, format!("{}", e))),
        }
    }

    // Return tuple (succeeded_count, failed_list)
    Ok((succeeded, failed).encode(env))
}

/// Helper function to encode ObjectMeta to an Elixir map
fn encode_object_meta_for_list<'a>(env: Env<'a>, meta: &object_store::ObjectMeta) -> Term<'a> {
    use rustler::types::atom::Atom;
    use rustler::types::map;

    let map = map::map_new(env);

    let map = map
        .map_put(
            Atom::from_str(env, "location").unwrap().to_term(env),
            meta.location.to_string().encode(env),
        )
        .unwrap();

    let map = map
        .map_put(
            Atom::from_str(env, "size").unwrap().to_term(env),
            meta.size.encode(env),
        )
        .unwrap();

    let map = map
        .map_put(
            Atom::from_str(env, "last_modified")
                .unwrap()
                .to_term(env),
            meta.last_modified.to_string().encode(env),
        )
        .unwrap();

    let map = if let Some(ref etag) = meta.e_tag {
        map.map_put(
            Atom::from_str(env, "etag").unwrap().to_term(env),
            etag.encode(env),
        )
        .unwrap()
    } else {
        map
    };

    let map = map
        .map_put(
            Atom::from_str(env, "version").unwrap().to_term(env),
            meta.version.as_ref().map(|v| v.to_string()).encode(env),
        )
        .unwrap();

    map
}

/// List objects with delimiter, returning objects and common prefixes separately
#[rustler::nif(schedule = "DirtyCpu")]
pub fn list_with_delimiter<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    prefix: Option<String>,
) -> NifResult<Term<'a>> {
    let prefix_path = prefix.map(Path::from);

    let result = RUNTIME.block_on(async {
        store
            .inner
            .list_with_delimiter(prefix_path.as_ref())
            .await
    });

    match result {
        Ok(list_result) => {
            // Convert objects to Elixir terms
            let objects: Vec<Term> = list_result
                .objects
                .iter()
                .map(|meta| encode_object_meta_for_list(env, meta))
                .collect();

            // Convert prefixes to strings
            let prefixes: Vec<String> = list_result
                .common_prefixes
                .iter()
                .map(|p| p.to_string())
                .collect();

            // Return tuple (objects, prefixes)
            Ok((objects, prefixes).encode(env))
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}
