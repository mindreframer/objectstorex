defmodule ObjectStoreX.Errors do
  @moduledoc """
  Error types and documentation for ObjectStoreX.

  All errors returned from the native Rust layer are mapped to atoms
  for easy pattern matching in Elixir code.

  ## Error Types

  - `:ok` - Operation succeeded (not an error)
  - `:error` - Generic error (catch-all for unexpected errors)
  - `:not_found` - Object does not exist at the specified path
  - `:already_exists` - Object already exists (used in conditional operations)
  - `:precondition_failed` - A precondition for the operation was not met
  - `:not_modified` - Object was not modified (used for caching/conditional requests)
  - `:not_supported` - Operation is not supported by this storage provider
  - `:permission_denied` - Insufficient permissions to perform the operation

  ## Error Descriptions

  ### `:not_found`
  Returned when attempting to access an object that doesn't exist.

  **Common causes:**
  - Attempting to `get/2` a file that was never uploaded
  - Attempting to `head/2` on a non-existent path
  - Attempting to `copy/3` or `rename/3` from a non-existent source

  **Example:**
      {:error, :not_found} = ObjectStoreX.get(store, "missing.txt")

  ### `:already_exists`
  Returned when attempting to create an object that already exists
  (typically in conditional operations with if-not-exists semantics).

  **Common causes:**
  - Provider-specific conditional put operations
  - Race conditions in multi-client scenarios

  ### `:precondition_failed`
  Returned when a conditional operation's precondition is not satisfied.

  **Common causes:**
  - ETag mismatch in conditional operations
  - Version mismatch in versioned storage
  - If-Match or If-None-Match header failures

  ### `:not_modified`
  Returned when a conditional request determines the object hasn't changed.

  **Common causes:**
  - ETag matches in conditional GET requests
  - Last-Modified checks indicate no changes

  ### `:not_supported`
  Returned when attempting an operation not supported by the storage provider.

  **Common causes:**
  - Using `rename/3` on providers that don't support atomic rename
  - Provider-specific feature limitations
  - Some providers don't support server-side copy operations

  **Example:**
      # Some operations may not be supported by all providers
      case ObjectStoreX.rename(store, "old.txt", "new.txt") do
        :ok -> :ok
        {:error, :not_supported} ->
          # Fall back to copy + delete
          with :ok <- ObjectStoreX.copy(store, "old.txt", "new.txt"),
               :ok <- ObjectStoreX.delete(store, "old.txt") do
            :ok
          end
      end

  ### `:permission_denied`
  Returned when the credentials lack permissions for the requested operation.

  **Common causes:**
  - Invalid or expired credentials
  - IAM/access policies don't grant required permissions
  - Attempting to write to a read-only location
  - Bucket policies or ACLs deny access

  **Example:**
      {:error, :permission_denied} = ObjectStoreX.put(store, "protected/file.txt", data)

  ### `:error`
  Generic error atom returned for unexpected errors that don't fit other categories.

  **Common causes:**
  - Network errors (connection timeouts, DNS failures)
  - Malformed requests
  - Internal server errors (500s)
  - Serialization/deserialization failures

  ## Error Handling Patterns

  ### Pattern Matching
      case ObjectStoreX.get(store, path) do
        {:ok, data} ->
          process_data(data)
        {:error, :not_found} ->
          Logger.info("File not found: \#{path}")
          :ok
        {:error, :permission_denied} ->
          Logger.error("Access denied: \#{path}")
          {:error, :unauthorized}
        {:error, reason} ->
          Logger.error("Unexpected error: \#{inspect(reason)}")
          {:error, :internal}
      end

  ### With Clause
      with {:ok, store} <- ObjectStoreX.new(:s3, config),
           :ok <- ObjectStoreX.put(store, "test.txt", "data"),
           {:ok, data} <- ObjectStoreX.get(store, "test.txt") do
        {:ok, data}
      else
        {:error, :permission_denied} -> {:error, :unauthorized}
        {:error, reason} -> {:error, reason}
      end

  ### Rescue Blocks
  All public API functions include rescue blocks that convert exceptions
  to `{:error, message}` tuples, so you typically don't need to rescue
  exceptions when using ObjectStoreX.

      # This is safe - exceptions are caught internally
      case ObjectStoreX.get(store, path) do
        {:ok, data} -> {:ok, data}
        {:error, reason} -> {:error, reason}
      end
  """

  @type error_atom ::
          :ok
          | :error
          | :not_found
          | :already_exists
          | :precondition_failed
          | :not_modified
          | :not_supported
          | :permission_denied

  @doc """
  Returns a human-readable description of an error atom.

  ## Examples

      iex> ObjectStoreX.Errors.describe(:not_found)
      "Object does not exist at the specified path"

      iex> ObjectStoreX.Errors.describe(:permission_denied)
      "Insufficient permissions to perform the operation"
  """
  @spec describe(error_atom()) :: String.t()
  def describe(:ok), do: "Operation succeeded"
  def describe(:error), do: "Generic error occurred"
  def describe(:not_found), do: "Object does not exist at the specified path"

  def describe(:already_exists),
    do: "Object already exists (used in conditional operations)"

  def describe(:precondition_failed), do: "A precondition for the operation was not met"
  def describe(:not_modified), do: "Object was not modified"
  def describe(:not_supported), do: "Operation is not supported by this storage provider"

  def describe(:permission_denied),
    do: "Insufficient permissions to perform the operation"

  def describe(other), do: "Unknown error: #{inspect(other)}"
end
