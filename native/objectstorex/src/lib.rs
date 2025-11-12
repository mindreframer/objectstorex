use rustler::Env;
use once_cell::sync::Lazy;
use tokio::runtime::Runtime;

mod atoms;
mod store;
mod builders;
mod operations;
mod errors;

use store::StoreWrapper;

// Lazy static Tokio runtime for async operations
pub(crate) static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    tokio::runtime::Runtime::new()
        .expect("Failed to create Tokio runtime")
});

// Initialize the NIF module
rustler::init!(
    "Elixir.ObjectStoreX.Native",
    load = on_load
);

#[allow(non_local_definitions)]
fn on_load(env: Env, _info: rustler::Term) -> bool {
    let _ = rustler::resource!(StoreWrapper, env);
    true
}
