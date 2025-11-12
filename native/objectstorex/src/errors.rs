use object_store::Error as ObjectStoreError;
use rustler::Atom;
use crate::atoms;

/// Map object_store errors to Elixir atoms
#[allow(dead_code)]
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
