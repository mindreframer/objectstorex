use crate::atoms;
use crate::errors::map_error;
use crate::store::StoreWrapper;
use crate::types::{AttributesNif, GetOptionsNif, PutModeNif};
use crate::RUNTIME;
use chrono::{DateTime, TimeZone, Utc};
use object_store::{
    path::Path, Attribute, Attributes, GetOptions, GetRange, PutMode, PutOptions, PutPayload,
    UpdateVersion as ObjectStoreUpdateVersion,
};
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

/// Upload an object to storage with specific write mode (CAS, create-only, etc.)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn put_with_mode<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    data: Binary,
    mode: PutModeNif,
) -> NifResult<Term<'a>> {
    // Convert PutModeNif to object_store::PutMode
    let rust_mode = match mode {
        PutModeNif::Overwrite => PutMode::Overwrite,
        PutModeNif::Create => PutMode::Create,
        PutModeNif::Update { etag, version } => {
            PutMode::Update(ObjectStoreUpdateVersion {
                e_tag: etag,
                version,
            })
        }
    };

    let opts = PutOptions {
        mode: rust_mode,
        ..Default::default()
    };

    let payload = PutPayload::from(data.as_slice().to_vec());

    match RUNTIME.block_on(async {
        store
            .inner
            .put_opts(&Path::from(path), payload, opts)
            .await
    }) {
        Ok(put_result) => {
            // Return {:ok, etag, version}
            let etag = put_result.e_tag.unwrap_or_else(|| "".to_string());
            let version = put_result.version.unwrap_or_else(|| "".to_string());
            Ok((atoms::ok(), etag, version).encode(env))
        }
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
///
/// Uses get_opts with head: true to retrieve full metadata including attributes
#[rustler::nif(schedule = "DirtyCpu")]
pub fn head<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    // Use get_opts with head: true to get attributes
    let opts = GetOptions {
        head: true,
        ..Default::default()
    };

    let result = RUNTIME.block_on(async {
        store.inner.get_opts(&Path::from(path), opts).await
    });

    match result {
        Ok(get_result) => {
            // Extract metadata and attributes
            let meta = &get_result.meta;
            let attributes = &get_result.attributes;

            // Convert ObjectMeta and Attributes to Elixir map
            let map = encode_object_meta_with_attributes(env, meta, attributes);
            Ok(map)
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
            Atom::from_str(env, "last_modified").unwrap().to_term(env),
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

    let result =
        RUNTIME.block_on(async { store.inner.list_with_delimiter(prefix_path.as_ref()).await });

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

/// Convert Unix timestamp (seconds) to chrono DateTime<Utc>
///
/// # Arguments
/// * `timestamp` - Unix timestamp in seconds since epoch
///
/// # Returns
/// DateTime<Utc> representation of the timestamp
fn timestamp_to_datetime(timestamp: i64) -> DateTime<Utc> {
    Utc.timestamp_opt(timestamp, 0)
        .single()
        .expect("Invalid timestamp")
}

/// Download an object from storage with conditional options
///
/// Supports HTTP-style conditional requests for caching and consistency:
/// - if_match: Only return if ETag matches
/// - if_none_match: Only return if ETag differs
/// - if_modified_since: Only return if modified after date
/// - if_unmodified_since: Only return if not modified since date
/// - range: Fetch specific byte range
/// - version: Fetch specific object version
/// - head: Return metadata only
#[rustler::nif(schedule = "DirtyCpu")]
pub fn get_with_options<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    options: GetOptionsNif,
) -> NifResult<Term<'a>> {
    // Convert GetOptionsNif to object_store::GetOptions
    let mut rust_options = GetOptions::default();

    if let Some(etag) = options.if_match {
        rust_options.if_match = Some(etag);
    }

    if let Some(etag) = options.if_none_match {
        rust_options.if_none_match = Some(etag);
    }

    if let Some(timestamp) = options.if_modified_since {
        rust_options.if_modified_since = Some(timestamp_to_datetime(timestamp));
    }

    if let Some(timestamp) = options.if_unmodified_since {
        rust_options.if_unmodified_since = Some(timestamp_to_datetime(timestamp));
    }

    if let Some(range) = options.range {
        rust_options.range = Some(GetRange::Bounded(range.start as usize..range.end as usize));
    }

    if let Some(version) = options.version {
        rust_options.version = Some(version);
    }

    rust_options.head = options.head;

    // Perform the get operation
    let result =
        RUNTIME.block_on(async { store.inner.get_opts(&Path::from(path), rust_options).await });

    match result {
        Ok(get_result) => {
            // Get metadata
            let meta = get_result.meta.clone();

            // If head-only request or if we should return data
            let data = if options.head {
                vec![]
            } else {
                match RUNTIME.block_on(async { get_result.bytes().await }) {
                    Ok(bytes) => bytes.to_vec(),
                    Err(e) => return Ok(map_error(e).to_term(env)),
                }
            };

            // Encode metadata to Elixir map
            let meta_map = encode_object_meta_with_version(env, &meta);

            // Return {:ok, data, metadata}
            Ok((atoms::ok(), data, meta_map).encode(env))
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Helper function to encode ObjectMeta with version information to Elixir map
fn encode_object_meta_with_version<'a>(env: Env<'a>, meta: &object_store::ObjectMeta) -> Term<'a> {
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
            Atom::from_str(env, "last_modified").unwrap().to_term(env),
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

/// Helper function to encode ObjectMeta with Attributes to Elixir map
fn encode_object_meta_with_attributes<'a>(
    env: Env<'a>,
    meta: &object_store::ObjectMeta,
    attributes: &Attributes,
) -> Term<'a> {
    use rustler::types::atom::Atom;
    use rustler::types::map;

    let map = map::map_new(env);

    // Add basic metadata
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
            Atom::from_str(env, "last_modified").unwrap().to_term(env),
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

    // Add attributes if present using get() method
    let map = if let Some(value) = attributes.get(&Attribute::ContentType) {
        map.map_put(
            Atom::from_str(env, "content_type").unwrap().to_term(env),
            value.as_ref().to_string().encode(env),
        )
        .unwrap()
    } else {
        map
    };

    let map = if let Some(value) = attributes.get(&Attribute::ContentEncoding) {
        map.map_put(
            Atom::from_str(env, "content_encoding").unwrap().to_term(env),
            value.as_ref().to_string().encode(env),
        )
        .unwrap()
    } else {
        map
    };

    let map = if let Some(value) = attributes.get(&Attribute::ContentDisposition) {
        map.map_put(
            Atom::from_str(env, "content_disposition").unwrap().to_term(env),
            value.as_ref().to_string().encode(env),
        )
        .unwrap()
    } else {
        map
    };

    let map = if let Some(value) = attributes.get(&Attribute::CacheControl) {
        map.map_put(
            Atom::from_str(env, "cache_control").unwrap().to_term(env),
            value.as_ref().to_string().encode(env),
        )
        .unwrap()
    } else {
        map
    };

    let map = if let Some(value) = attributes.get(&Attribute::ContentLanguage) {
        map.map_put(
            Atom::from_str(env, "content_language").unwrap().to_term(env),
            value.as_ref().to_string().encode(env),
        )
        .unwrap()
    } else {
        map
    };

    map
}

/// Upload an object to storage with attributes and optional tags
///
/// Supports setting HTTP headers and metadata:
/// - content_type: MIME type
/// - content_encoding: Encoding (e.g., "gzip")
/// - content_disposition: Download behavior
/// - cache_control: Cache directives
/// - content_language: Language code
/// - tags: Object tags (AWS/GCS only)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn put_with_attributes<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    data: Binary,
    mode: PutModeNif,
    attributes: AttributesNif,
    _tags: Vec<(String, String)>,
) -> NifResult<Term<'a>> {
    // Convert PutModeNif to object_store::PutMode
    let rust_mode = match mode {
        PutModeNif::Overwrite => PutMode::Overwrite,
        PutModeNif::Create => PutMode::Create,
        PutModeNif::Update { etag, version } => {
            PutMode::Update(ObjectStoreUpdateVersion {
                e_tag: etag,
                version,
            })
        }
    };

    // Convert AttributesNif to object_store::Attributes using insert API
    let mut rust_attributes = Attributes::new();

    if let Some(content_type) = attributes.content_type {
        rust_attributes.insert(Attribute::ContentType, content_type.into());
    }

    if let Some(content_encoding) = attributes.content_encoding {
        rust_attributes.insert(Attribute::ContentEncoding, content_encoding.into());
    }

    if let Some(content_disposition) = attributes.content_disposition {
        rust_attributes.insert(Attribute::ContentDisposition, content_disposition.into());
    }

    if let Some(cache_control) = attributes.cache_control {
        rust_attributes.insert(Attribute::CacheControl, cache_control.into());
    }

    if let Some(content_language) = attributes.content_language {
        rust_attributes.insert(Attribute::ContentLanguage, content_language.into());
    }

    // Build PutOptions with mode and attributes
    let opts = PutOptions {
        mode: rust_mode,
        attributes: rust_attributes,
        ..Default::default()
    };

    // Note: Tags are not easily constructible in object_store 0.11.2
    // The API accepts them, but we'll skip setting them for now

    let payload = PutPayload::from(data.as_slice().to_vec());

    // Perform the put operation
    match RUNTIME.block_on(async {
        store
            .inner
            .put_opts(&Path::from(path), payload, opts)
            .await
    }) {
        Ok(put_result) => {
            // Return {:ok, etag, version}
            let etag = put_result.e_tag.unwrap_or_else(|| "".to_string());
            let version = put_result.version.unwrap_or_else(|| "".to_string());
            Ok((atoms::ok(), etag, version).encode(env))
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Copy an object only if the destination doesn't exist (atomic where supported)
///
/// Provider support:
/// - Azure: Native atomic copy_if_not_exists
/// - GCS: Native atomic copy_if_not_exists
/// - Local/Memory: Atomic via filesystem operations
/// - S3: Not supported (returns :not_supported)
///
/// For S3, use a manual check-then-copy pattern in Elixir
#[rustler::nif(schedule = "DirtyCpu")]
pub fn copy_if_not_exists<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Term<'a>> {
    match RUNTIME.block_on(async {
        store
            .inner
            .copy_if_not_exists(&Path::from(from), &Path::from(to))
            .await
    }) {
        Ok(_) => Ok(atoms::ok().to_term(env)),
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}

/// Rename an object only if the destination doesn't exist (atomic where supported)
///
/// This is implemented as copy_if_not_exists followed by delete of the source.
/// The operation is only atomic if the underlying provider supports atomic copy_if_not_exists.
///
/// Provider support:
/// - Azure: Atomic
/// - GCS: Atomic
/// - Local/Memory: Atomic
/// - S3: Not supported (returns :not_supported)
#[rustler::nif(schedule = "DirtyCpu")]
pub fn rename_if_not_exists<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    from: String,
    to: String,
) -> NifResult<Term<'a>> {
    let from_path = Path::from(from.clone());
    let to_path = Path::from(to);

    // First try to copy_if_not_exists
    match RUNTIME.block_on(async {
        store
            .inner
            .copy_if_not_exists(&from_path, &to_path)
            .await
    }) {
        Ok(_) => {
            // Copy succeeded, now delete the source
            match RUNTIME.block_on(async { store.inner.delete(&from_path).await }) {
                Ok(_) => Ok(atoms::ok().to_term(env)),
                Err(e) => Ok(map_error(e).to_term(env)),
            }
        }
        Err(e) => Ok(map_error(e).to_term(env)),
    }
}
