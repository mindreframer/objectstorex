use crate::atoms;
use crate::store::StoreWrapper;
use crate::RUNTIME;
use bytes::Bytes;
use futures::StreamExt;
use object_store::path::Path;
use object_store::{MultipartUpload, PutPayload};
use rustler::{Binary, Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use tokio::sync::Mutex as TokioMutex;
use tokio::task::JoinHandle;
use uuid::Uuid;

// Type alias to reduce complexity
type StreamRegistry = Arc<Mutex<HashMap<String, JoinHandle<()>>>>;

// Global registry to track active download streams for cancellation
static STREAM_REGISTRY: once_cell::sync::Lazy<StreamRegistry> =
    once_cell::sync::Lazy::new(|| Arc::new(Mutex::new(HashMap::new())));

/// Start a download stream that sends chunks to the receiver process
#[rustler::nif]
pub fn start_download_stream<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
    receiver_pid: LocalPid,
) -> NifResult<Term<'a>> {
    let stream_id = Uuid::new_v4().to_string();
    let stream_id_clone = stream_id.clone();
    let store = store.inner.clone();
    let path_obj = Path::from(path);

    // Spawn async task to stream chunks
    let handle = RUNTIME.spawn(async move {
        let result = store.get(&path_obj).await;

        match result {
            Ok(get_result) => {
                let mut stream = get_result.into_stream();

                // Stream chunks to Elixir process
                while let Some(chunk_result) = stream.next().await {
                    match chunk_result {
                        Ok(bytes) => {
                            // Send chunk message to Elixir process
                            if !send_chunk(&receiver_pid, &stream_id_clone, bytes) {
                                // If send fails, process is dead, stop streaming
                                return;
                            }
                        }
                        Err(e) => {
                            send_error(&receiver_pid, &stream_id_clone, format!("{}", e));
                            return;
                        }
                    }
                }

                // Send completion message
                send_done(&receiver_pid, &stream_id_clone);
            }
            Err(e) => {
                send_error(&receiver_pid, &stream_id_clone, format!("{}", e));
            }
        }
    });

    // Register the task handle for cancellation
    {
        let mut registry = STREAM_REGISTRY.lock().unwrap();
        registry.insert(stream_id.clone(), handle);
    }

    // Return {:ok, stream_id}
    Ok((atoms::ok(), stream_id).encode(env))
}

/// Cancel an active download stream
#[rustler::nif]
pub fn cancel_download_stream<'a>(env: Env<'a>, stream_id: String) -> NifResult<Term<'a>> {
    let handle_opt = {
        let mut registry = STREAM_REGISTRY.lock().unwrap();
        registry.remove(&stream_id)
    };

    if let Some(handle) = handle_opt {
        handle.abort();
    }

    Ok(atoms::ok().encode(env))
}

// Helper function to send chunk message to Elixir process
fn send_chunk(receiver_pid: &LocalPid, stream_id: &str, bytes: Bytes) -> bool {
    let mut env = OwnedEnv::new();

    let _ = env.send_and_clear(receiver_pid, |env| {
        let chunk_atom = atoms::chunk().encode(env);
        let id_term = stream_id.encode(env);

        // Convert bytes to Binary for Elixir
        let mut binary = rustler::OwnedBinary::new(bytes.len()).unwrap();
        binary.as_mut_slice().copy_from_slice(&bytes);
        let data = binary.release(env);

        (chunk_atom, id_term, data).encode(env)
    });

    true
}

// Helper function to send done message to Elixir process
fn send_done(receiver_pid: &LocalPid, stream_id: &str) {
    let mut env = OwnedEnv::new();

    let _ = env.send_and_clear(receiver_pid, |env| {
        let done_atom = atoms::done().encode(env);
        let id_term = stream_id.encode(env);
        (done_atom, id_term).encode(env)
    });
}

// Helper function to send error message to Elixir process
fn send_error(receiver_pid: &LocalPid, stream_id: &str, error_msg: String) {
    let mut env = OwnedEnv::new();

    let _ = env.send_and_clear(receiver_pid, |env| {
        let error_atom = atoms::error().encode(env);
        let id_term = stream_id.encode(env);
        let msg_term = error_msg.encode(env);
        (error_atom, id_term, msg_term).encode(env)
    });
}

// ============================================================================
// Upload Streaming (Multipart Upload)
// ============================================================================

/// Wrapper for multipart upload session
pub struct UploadSessionWrapper {
    _session_id: String,
    multipart: Arc<TokioMutex<Box<dyn MultipartUpload>>>,
    buffer: Arc<Mutex<Vec<u8>>>,
    part_size: usize,
}

/// Start a new multipart upload session
#[rustler::nif(schedule = "DirtyCpu")]
pub fn start_upload_session<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    path: String,
) -> NifResult<Term<'a>> {
    let session_id = Uuid::new_v4().to_string();
    let path_obj = Path::from(path);

    // Initialize multipart upload
    let multipart = RUNTIME
        .block_on(async { store.inner.put_multipart(&path_obj).await })
        .map_err(|e| {
            rustler::Error::Term(Box::new(format!(
                "Failed to initialize multipart upload: {}",
                e
            )))
        })?;

    let session = UploadSessionWrapper {
        _session_id: session_id.clone(),
        multipart: Arc::new(TokioMutex::new(multipart)),
        buffer: Arc::new(Mutex::new(Vec::new())),
        part_size: 5 * 1024 * 1024, // 5MB minimum part size
    };

    let resource = ResourceArc::new(session);

    // Return {:ok, resource}
    Ok((atoms::ok(), resource).encode(env))
}

/// Upload a chunk of data to the multipart upload session
#[rustler::nif(schedule = "DirtyCpu")]
pub fn upload_chunk<'a>(
    env: Env<'a>,
    session: ResourceArc<UploadSessionWrapper>,
    chunk: Binary,
) -> NifResult<Term<'a>> {
    // Append chunk to buffer
    {
        let mut buffer = session
            .buffer
            .lock()
            .map_err(|e| rustler::Error::Term(Box::new(format!("Buffer lock error: {}", e))))?;
        buffer.extend_from_slice(chunk.as_slice());
    }

    // Check if we need to upload a part
    let should_upload = {
        let buffer = session
            .buffer
            .lock()
            .map_err(|e| rustler::Error::Term(Box::new(format!("Buffer lock error: {}", e))))?;
        buffer.len() >= session.part_size
    };

    if should_upload {
        // Extract data from buffer
        let data = {
            let mut buffer = session
                .buffer
                .lock()
                .map_err(|e| rustler::Error::Term(Box::new(format!("Buffer lock error: {}", e))))?;
            buffer.drain(..).collect::<Vec<u8>>()
        };

        // Upload the part
        let payload = PutPayload::from(data);
        let multipart_clone = session.multipart.clone();

        RUNTIME
            .block_on(async move {
                let mut multipart = multipart_clone.lock().await;
                multipart.put_part(payload).await
            })
            .map_err(|e| rustler::Error::Term(Box::new(format!("Failed to upload part: {}", e))))?;
    }

    Ok(atoms::ok().encode(env))
}

/// Complete the multipart upload
#[rustler::nif(schedule = "DirtyCpu")]
pub fn complete_upload<'a>(
    env: Env<'a>,
    session: ResourceArc<UploadSessionWrapper>,
) -> NifResult<Term<'a>> {
    // Upload any remaining data in the buffer as the final part
    let remaining_data = {
        let mut buffer = session
            .buffer
            .lock()
            .map_err(|e| rustler::Error::Term(Box::new(format!("Buffer lock error: {}", e))))?;
        buffer.drain(..).collect::<Vec<u8>>()
    };

    // Upload final part if there's remaining data
    if !remaining_data.is_empty() {
        let payload = PutPayload::from(remaining_data);
        let multipart_clone = session.multipart.clone();

        RUNTIME
            .block_on(async move {
                let mut multipart = multipart_clone.lock().await;
                multipart.put_part(payload).await
            })
            .map_err(|e| {
                rustler::Error::Term(Box::new(format!("Failed to upload final part: {}", e)))
            })?;
    }

    // Complete the multipart upload
    let multipart_clone = session.multipart.clone();
    RUNTIME
        .block_on(async move {
            let mut multipart = multipart_clone.lock().await;
            multipart.complete().await
        })
        .map_err(|e| rustler::Error::Term(Box::new(format!("Failed to complete upload: {}", e))))?;

    Ok(atoms::ok().encode(env))
}

/// Abort the multipart upload
#[rustler::nif(schedule = "DirtyCpu")]
pub fn abort_upload<'a>(
    env: Env<'a>,
    session: ResourceArc<UploadSessionWrapper>,
) -> NifResult<Term<'a>> {
    let multipart_clone = session.multipart.clone();

    RUNTIME
        .block_on(async move {
            let mut multipart = multipart_clone.lock().await;
            multipart.abort().await
        })
        .map_err(|e| rustler::Error::Term(Box::new(format!("Failed to abort upload: {}", e))))?;

    Ok(atoms::ok().encode(env))
}

// ============================================================================
// List Operations (Streaming)
// ============================================================================

// Type alias for list stream registry
type ListRegistry = Arc<Mutex<HashMap<String, JoinHandle<()>>>>;

// Global registry to track active list streams for potential cancellation
static LIST_REGISTRY: once_cell::sync::Lazy<ListRegistry> =
    once_cell::sync::Lazy::new(|| Arc::new(Mutex::new(HashMap::new())));

/// Helper function to encode ObjectMeta to an Elixir map
fn encode_object_meta<'a>(env: Env<'a>, meta: &object_store::ObjectMeta) -> Term<'a> {
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

/// Start a list stream that sends object metadata to the receiver process
#[rustler::nif]
pub fn start_list_stream<'a>(
    env: Env<'a>,
    store: ResourceArc<StoreWrapper>,
    prefix: Option<String>,
    receiver_pid: LocalPid,
) -> NifResult<Term<'a>> {
    let list_id = Uuid::new_v4().to_string();
    let list_id_clone = list_id.clone();
    let store = store.inner.clone();
    let prefix_path = prefix.map(Path::from);

    // Spawn async task to list objects
    let handle = RUNTIME.spawn(async move {
        let mut stream = store.list(prefix_path.as_ref());

        // Iterate over the stream and send each object metadata
        while let Some(meta_result) = stream.next().await {
            match meta_result {
                Ok(meta) => {
                    // Send object metadata to Elixir process
                    if !send_object(&receiver_pid, &list_id_clone, meta) {
                        // If send fails, process is dead, stop listing
                        return;
                    }
                }
                Err(e) => {
                    send_error(&receiver_pid, &list_id_clone, format!("{}", e));
                    return;
                }
            }
        }

        // Send completion message
        send_done(&receiver_pid, &list_id_clone);
    });

    // Register the task handle
    {
        let mut registry = LIST_REGISTRY.lock().unwrap();
        registry.insert(list_id.clone(), handle);
    }

    // Return {:ok, list_id}
    Ok((atoms::ok(), list_id).encode(env))
}

/// Helper function to send object metadata message to Elixir process
fn send_object(receiver_pid: &LocalPid, list_id: &str, meta: object_store::ObjectMeta) -> bool {
    let mut env = OwnedEnv::new();

    let _ = env.send_and_clear(receiver_pid, |env| {
        let object_atom = atoms::object().encode(env);
        let id_term = list_id.encode(env);
        let meta_map = encode_object_meta(env, &meta);

        (object_atom, id_term, meta_map).encode(env)
    });

    true
}
