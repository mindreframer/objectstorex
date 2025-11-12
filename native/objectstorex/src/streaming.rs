use crate::atoms;
use crate::store::StoreWrapper;
use crate::RUNTIME;
use bytes::Bytes;
use futures::StreamExt;
use object_store::path::Path;
use rustler::{Encoder, Env, LocalPid, NifResult, OwnedEnv, ResourceArc, Term};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
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

