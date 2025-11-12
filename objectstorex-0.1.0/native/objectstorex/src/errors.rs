use crate::atoms;
use object_store::Error as ObjectStoreError;
use rustler::Atom;

/// Map object_store errors to Elixir atoms for consistent error handling
///
/// This function converts Rust object_store errors into Elixir atoms that can
/// be easily pattern-matched on the Elixir side.
///
/// # Error Mapping
///
/// - `NotFound` → `:not_found` - Object doesn't exist at the specified path
/// - `AlreadyExists` → `:already_exists` - Object already exists (conditional ops)
/// - `Precondition` → `:precondition_failed` - Precondition not met (ETag mismatch, etc.)
/// - `NotModified` → `:not_modified` - Object not modified (conditional requests)
/// - `NotSupported` → `:not_supported` - Operation not supported by provider
/// - `PermissionDenied` → `:permission_denied` - Insufficient permissions
/// - All other errors → `:error` - Generic error (network, internal, etc.)
///
/// # Examples
///
/// ```rust
/// use object_store::Error as ObjectStoreError;
///
/// let error = ObjectStoreError::NotFound { path: "test.txt".to_string(), source: ... };
/// let atom = map_error(error);
/// // atom is now :not_found
/// ```
pub fn map_error(error: ObjectStoreError) -> Atom {
    match error {
        ObjectStoreError::NotFound { .. } => atoms::not_found(),
        ObjectStoreError::AlreadyExists { .. } => atoms::already_exists(),
        ObjectStoreError::Precondition { .. } => atoms::precondition_failed(),
        ObjectStoreError::NotModified { .. } => atoms::not_modified(),
        ObjectStoreError::NotSupported { .. } => atoms::not_supported(),
        ObjectStoreError::PermissionDenied { .. } => atoms::permission_denied(),
        _ => atoms::error(),
    }
}
