use object_store::DynObjectStore;
use std::panic::RefUnwindSafe;
use std::sync::Arc;

/// Wrapper around the object_store DynObjectStore trait object
/// This is registered as a Rustler resource to be passed between Elixir and Rust
pub struct StoreWrapper {
    pub inner: Arc<DynObjectStore>,
}

impl StoreWrapper {
    pub fn new(store: Arc<DynObjectStore>) -> Self {
        Self { inner: store }
    }
}

// Implement RefUnwindSafe to satisfy Rustler's requirements
impl RefUnwindSafe for StoreWrapper {}
