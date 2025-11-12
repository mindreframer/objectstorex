use once_cell::sync::Lazy;
use rustler::Env;
use tokio::runtime::Runtime;

mod atoms;
mod builders;
mod errors;
mod operations;
mod store;
mod streaming;

use store::StoreWrapper;
use streaming::UploadSessionWrapper;

// Lazy static Tokio runtime for async operations
pub(crate) static RUNTIME: Lazy<Runtime> =
    Lazy::new(|| tokio::runtime::Runtime::new().expect("Failed to create Tokio runtime"));

// Initialize the NIF module
rustler::init!("Elixir.ObjectStoreX.Native", load = on_load);

#[allow(non_local_definitions)]
fn on_load(env: Env, _info: rustler::Term) -> bool {
    let _ = rustler::resource!(StoreWrapper, env);
    let _ = rustler::resource!(UploadSessionWrapper, env);
    true
}
