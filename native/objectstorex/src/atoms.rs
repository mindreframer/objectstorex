// Define Elixir atoms used for return values and error types
rustler::atoms! {
    ok,
    error,
    not_found,
    already_exists,
    precondition_failed,
    not_modified,
    not_supported,
    permission_denied,
    // Streaming atoms
    chunk,
    done,
}
