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
