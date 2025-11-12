defmodule ObjectStoreX.Error do
  @moduledoc """
  Error types and handling for ObjectStoreX.

  This module provides comprehensive error handling with descriptive error types,
  context information, and utilities for retry logic.

  ## Error Types

  All ObjectStoreX operations return tagged tuples:
  - `{:ok, result}` on success
  - `{:error, reason}` on failure

  The `reason` can be either a simple atom or a tuple with context:
  - `:not_found` - Object doesn't exist
  - `:already_exists` - Object exists (create-only mode)
  - `:precondition_failed` - Conditional operation failed
  - `:not_modified` - Object not modified (conditional GET)
  - `:permission_denied` - Insufficient permissions
  - `:not_supported` - Operation not supported by provider
  - `:timeout` - Operation timed out
  - `:network_error` - Network/connection error
  - `:invalid_input` - Invalid parameters
  - `{:unknown, message}` - Unknown error with details

  ## Error Context

  For detailed error information, errors can include context:

      {:error, {:permission_denied, %{
        operation: :put,
        path: "protected/file.txt",
        provider: :s3,
        message: "Access Denied"
      }}}

  ## Examples

      # Simple error handling
      case ObjectStoreX.get(store, "missing.txt") do
        {:ok, data} -> {:ok, data}
        {:error, :not_found} -> {:error, "File not found"}
        {:error, reason} -> {:error, ObjectStoreX.Error.format_error(reason)}
      end

      # Retry logic
      def get_with_retry(store, path, retries \\\\ 3) do
        case ObjectStoreX.get(store, path) do
          {:ok, data} -> {:ok, data}
          {:error, reason} when retries > 0 ->
            if ObjectStoreX.Error.retryable?(reason) do
              :timer.sleep(1000)
              get_with_retry(store, path, retries - 1)
            else
              {:error, reason}
            end
          {:error, reason} -> {:error, reason}
        end
      end
  """

  @type error_reason ::
          :not_found
          | :already_exists
          | :precondition_failed
          | :not_modified
          | :permission_denied
          | :not_supported
          | :timeout
          | :network_error
          | :invalid_input
          | {:unknown, String.t()}

  @type error_context :: %{
          optional(:operation) => atom(),
          optional(:path) => String.t(),
          optional(:provider) => atom(),
          optional(:message) => String.t()
        }

  @type detailed_error :: {error_reason(), error_context()}

  @doc """
  Formats an error for display.

  Returns a human-readable error message for any error reason.

  ## Examples

      iex> ObjectStoreX.Error.format_error(:not_found)
      "Object not found"

      iex> ObjectStoreX.Error.format_error(:permission_denied)
      "Permission denied"

      iex> ObjectStoreX.Error.format_error({:unknown, "Connection reset"})
      "Unknown error: Connection reset"

      iex> ObjectStoreX.Error.format_error({:permission_denied, %{path: "file.txt"}})
      "Permission denied"
  """
  @spec format_error(error_reason() | detailed_error() | any()) :: String.t()
  def format_error(:not_found), do: "Object not found"
  def format_error(:already_exists), do: "Object already exists"
  def format_error(:precondition_failed), do: "Precondition failed (ETag mismatch)"
  def format_error(:not_modified), do: "Object not modified"
  def format_error(:permission_denied), do: "Permission denied"
  def format_error(:not_supported), do: "Operation not supported by this provider"
  def format_error(:timeout), do: "Operation timed out"
  def format_error(:network_error), do: "Network error"
  def format_error(:invalid_input), do: "Invalid input parameters"
  def format_error({:unknown, msg}), do: "Unknown error: #{msg}"

  # Handle detailed errors with context
  def format_error({reason, context}) when is_atom(reason) and is_map(context) do
    format_error(reason)
  end

  # Handle any other error type
  def format_error(error), do: "Error: #{inspect(error)}"

  @doc """
  Returns true if the error is retryable.

  Retryable errors are transient and may succeed if retried.
  Non-retryable errors are permanent and will not succeed on retry.

  ## Retryable Errors
  - `:timeout` - Operation may succeed on retry
  - `:network_error` - Network may recover
  - `:precondition_failed` - For CAS retry with new ETag

  ## Non-Retryable Errors
  - `:not_found` - Object doesn't exist, retrying won't help
  - `:already_exists` - Object exists, retrying won't change that
  - `:permission_denied` - Credentials issue, won't fix on retry
  - `:not_supported` - Feature not supported, will never work
  - `:invalid_input` - Bad parameters, won't change on retry

  ## Examples

      iex> ObjectStoreX.Error.retryable?(:timeout)
      true

      iex> ObjectStoreX.Error.retryable?(:network_error)
      true

      iex> ObjectStoreX.Error.retryable?(:precondition_failed)
      true

      iex> ObjectStoreX.Error.retryable?(:not_found)
      false

      iex> ObjectStoreX.Error.retryable?(:permission_denied)
      false

      iex> ObjectStoreX.Error.retryable?({:timeout, %{path: "file.txt"}})
      true
  """
  @spec retryable?(error_reason() | detailed_error()) :: boolean()
  def retryable?(:timeout), do: true
  def retryable?(:network_error), do: true
  def retryable?(:precondition_failed), do: true  # For CAS retry

  # Non-retryable errors
  def retryable?(:not_found), do: false
  def retryable?(:already_exists), do: false
  def retryable?(:not_modified), do: false
  def retryable?(:permission_denied), do: false
  def retryable?(:not_supported), do: false
  def retryable?(:invalid_input), do: false
  def retryable?({:unknown, _}), do: false

  # Handle detailed errors with context
  def retryable?({reason, _context}) when is_atom(reason) do
    retryable?(reason)
  end

  # Unknown errors are not retryable
  def retryable?(_), do: false

  @doc """
  Creates an error with context information.

  Useful for adding operation-specific details to errors.

  ## Examples

      iex> ObjectStoreX.Error.with_context(:not_found, %{
      ...>   operation: :get,
      ...>   path: "missing.txt",
      ...>   provider: :s3
      ...> })
      {:not_found, %{operation: :get, path: "missing.txt", provider: :s3}}

      iex> ObjectStoreX.Error.with_context(:permission_denied, %{
      ...>   operation: :put,
      ...>   path: "protected/file.txt",
      ...>   message: "Access Denied"
      ...> })
      {:permission_denied, %{operation: :put, path: "protected/file.txt", message: "Access Denied"}}
  """
  @spec with_context(error_reason(), error_context()) :: detailed_error()
  def with_context(reason, context) when is_atom(reason) and is_map(context) do
    {reason, context}
  end

  @doc """
  Maps a generic error to a specific error reason.

  This is useful for converting string errors from NIFs or exceptions
  to standardized error atoms.

  ## Examples

      iex> ObjectStoreX.Error.map_error("not found")
      :not_found

      iex> ObjectStoreX.Error.map_error("NotFound: The specified key does not exist")
      :not_found

      iex> ObjectStoreX.Error.map_error("PermissionDenied: Access Denied")
      :permission_denied

      iex> ObjectStoreX.Error.map_error("timeout")
      :timeout

      iex> ObjectStoreX.Error.map_error("something weird")
      {:unknown, "something weird"}
  """
  @spec map_error(any()) :: error_reason()
  def map_error(msg) when is_binary(msg) do
    lower = String.downcase(msg)

    cond do
      String.contains?(lower, "not found") or String.contains?(lower, "notfound") or
          String.contains?(lower, "no such") or String.contains?(lower, "does not exist") ->
        :not_found

      String.contains?(lower, "already exists") or String.contains?(lower, "alreadyexists") ->
        :already_exists

      String.contains?(lower, "precondition") or String.contains?(lower, "etag") or
          String.contains?(lower, "if-match") ->
        :precondition_failed

      String.contains?(lower, "not modified") or String.contains?(lower, "notmodified") ->
        :not_modified

      String.contains?(lower, "permission") or String.contains?(lower, "denied") or
          String.contains?(lower, "unauthorized") or String.contains?(lower, "forbidden") or
          String.contains?(lower, "access denied") ->
        :permission_denied

      String.contains?(lower, "not supported") or String.contains?(lower, "notsupported") or
          String.contains?(lower, "unsupported") ->
        :not_supported

      String.contains?(lower, "timeout") or String.contains?(lower, "timed out") or
          String.contains?(lower, "deadline") ->
        :timeout

      String.contains?(lower, "network") or String.contains?(lower, "connection") or
          String.contains?(lower, "unreachable") or String.contains?(lower, "refused") or
          String.contains?(lower, "reset") ->
        :network_error

      String.contains?(lower, "invalid") or String.contains?(lower, "malformed") or
          String.contains?(lower, "bad request") ->
        :invalid_input

      true ->
        {:unknown, msg}
    end
  end

  # Map atom errors
  def map_error(:not_found), do: :not_found
  def map_error(:already_exists), do: :already_exists
  def map_error(:precondition_failed), do: :precondition_failed
  def map_error(:not_modified), do: :not_modified
  def map_error(:permission_denied), do: :permission_denied
  def map_error(:not_supported), do: :not_supported
  def map_error(:timeout), do: :timeout
  def map_error(:network_error), do: :network_error
  def map_error(:invalid_input), do: :invalid_input

  # Handle other types
  def map_error(error) do
    {:unknown, inspect(error)}
  end
end
