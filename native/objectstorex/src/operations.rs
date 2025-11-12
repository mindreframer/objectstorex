use rustler::{NifResult, ResourceArc, Error, Binary, Atom, Env, Term, OwnedBinary, Encoder};
use object_store::{path::Path, PutPayload};
use crate::store::StoreWrapper;
use crate::atoms;
use crate::RUNTIME;

/// Upload an object to storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn put(
    store: ResourceArc<StoreWrapper>,
    path: String,
    data: Binary,
) -> NifResult<Atom> {
    let payload = PutPayload::from(data.as_slice().to_vec());

    RUNTIME.block_on(async {
        store.inner.put(&Path::from(path), payload).await
    }).map_err(|e| Error::Term(Box::new(format!("Put error: {}", e))))?;

    Ok(atoms::ok())
}

/// Download an object from storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn get<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    let result = RUNTIME.block_on(async {
        store.inner.get(&Path::from(path)).await
    });

    match result {
        Ok(get_result) => {
            let bytes = RUNTIME.block_on(async {
                get_result.bytes().await
            }).map_err(|e| Error::Term(Box::new(format!("Read error: {}", e))))?;

            let mut binary = OwnedBinary::new(bytes.len()).unwrap();
            binary.as_mut_slice().copy_from_slice(&bytes);

            Ok(binary.release(env).to_term(env))
        }
        Err(object_store::Error::NotFound { .. }) => {
            Ok(atoms::not_found().to_term(env))
        }
        Err(e) => {
            Err(Error::Term(Box::new(format!("Get error: {}", e))))
        }
    }
}

/// Delete an object from storage
#[rustler::nif(schedule = "DirtyCpu")]
pub fn delete(
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Atom> {
    RUNTIME.block_on(async {
        store.inner.delete(&Path::from(path)).await
    }).map_err(|e| Error::Term(Box::new(format!("Delete error: {}", e))))?;

    Ok(atoms::ok())
}

/// Get object metadata without downloading content
#[rustler::nif(schedule = "DirtyCpu")]
pub fn head<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    let meta = RUNTIME.block_on(async {
        store.inner.head(&Path::from(path)).await
    });

    match meta {
        Ok(meta) => {
            // Convert ObjectMeta to Elixir map
            let map = rustler::types::map::map_new(env);
            let map = map.map_put(
                rustler::types::atom::Atom::from_str(env, "location").unwrap().to_term(env),
                meta.location.to_string().encode(env)
            ).ok().unwrap();
            let map = map.map_put(
                rustler::types::atom::Atom::from_str(env, "size").unwrap().to_term(env),
                meta.size.encode(env)
            ).ok().unwrap();
            let map = map.map_put(
                rustler::types::atom::Atom::from_str(env, "last_modified").unwrap().to_term(env),
                meta.last_modified.to_string().encode(env)
            ).ok().unwrap();

            if let Some(etag) = meta.e_tag {
                let map = map.map_put(
                    rustler::types::atom::Atom::from_str(env, "etag").unwrap().to_term(env),
                    etag.encode(env)
                ).ok().unwrap();
                Ok(map)
            } else {
                Ok(map)
            }
        }
        Err(object_store::Error::NotFound { .. }) => {
            Ok(atoms::not_found().to_term(env))
        }
        Err(e) => {
            Err(Error::Term(Box::new(format!("Head error: {}", e))))
        }
    }
}

/// Copy an object within storage (server-side)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn copy(
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Atom> {
    RUNTIME.block_on(async {
        store.inner.copy(&Path::from(from), &Path::from(to)).await
    }).map_err(|e| Error::Term(Box::new(format!("Copy error: {}", e))))?;

    Ok(atoms::ok())
}

/// Rename an object (server-side move)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn rename(
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Atom> {
    RUNTIME.block_on(async {
        store.inner.rename(&Path::from(from), &Path::from(to)).await
    }).map_err(|e| Error::Term(Box::new(format!("Rename error: {}", e))))?;

    Ok(atoms::ok())
}
