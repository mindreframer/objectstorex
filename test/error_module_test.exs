defmodule ObjectStoreX.ErrorModuleTest do
  use ExUnit.Case, async: true
  doctest ObjectStoreX.Error

  alias ObjectStoreX.Error

  describe "OBX004_1A_T1: Test format_error for all error types" do
    test "format_error returns correct messages for standard errors" do
      assert Error.format_error(:not_found) == "Object not found"
      assert Error.format_error(:already_exists) == "Object already exists"
      assert Error.format_error(:precondition_failed) == "Precondition failed (ETag mismatch)"
      assert Error.format_error(:not_modified) == "Object not modified"
      assert Error.format_error(:permission_denied) == "Permission denied"
      assert Error.format_error(:not_supported) == "Operation not supported by this provider"
      assert Error.format_error(:timeout) == "Operation timed out"
      assert Error.format_error(:network_error) == "Network error"
      assert Error.format_error(:invalid_input) == "Invalid input parameters"
    end

    test "format_error handles unknown errors with details" do
      assert Error.format_error({:unknown, "Connection reset"}) ==
               "Unknown error: Connection reset"

      assert Error.format_error({:unknown, "Unexpected failure"}) ==
               "Unknown error: Unexpected failure"
    end

    test "format_error handles detailed errors with context" do
      error = {:permission_denied, %{path: "file.txt", operation: :put}}
      assert Error.format_error(error) == "Permission denied"

      error = {:not_found, %{path: "missing.txt", provider: :s3}}
      assert Error.format_error(error) == "Object not found"
    end

    test "format_error handles arbitrary error types" do
      result = Error.format_error(:some_random_error)
      assert result =~ "Error:"
      assert result =~ "some_random_error"
    end
  end

  describe "OBX004_1A_T2: Test retryable? correctly identifies retryable errors" do
    test "retryable? returns true for transient errors" do
      assert Error.retryable?(:timeout) == true
      assert Error.retryable?(:network_error) == true
      assert Error.retryable?(:precondition_failed) == true
    end

    test "retryable? returns false for permanent errors" do
      assert Error.retryable?(:not_found) == false
      assert Error.retryable?(:already_exists) == false
      assert Error.retryable?(:not_modified) == false
      assert Error.retryable?(:permission_denied) == false
      assert Error.retryable?(:not_supported) == false
      assert Error.retryable?(:invalid_input) == false
    end

    test "retryable? returns false for unknown errors" do
      assert Error.retryable?({:unknown, "some error"}) == false
      assert Error.retryable?(:some_random_error) == false
    end

    test "retryable? handles detailed errors with context" do
      assert Error.retryable?({:timeout, %{path: "file.txt"}}) == true
      assert Error.retryable?({:network_error, %{message: "Connection reset"}}) == true
      assert Error.retryable?({:not_found, %{path: "missing.txt"}}) == false
    end
  end

  describe "OBX004_1A_T3: Test error context includes operation details" do
    test "with_context creates detailed error tuple" do
      context = %{
        operation: :get,
        path: "file.txt",
        provider: :s3
      }

      result = Error.with_context(:not_found, context)

      assert result == {:not_found, context}
    end

    test "with_context preserves all context fields" do
      context = %{
        operation: :put,
        path: "protected/file.txt",
        provider: :s3,
        message: "Access Denied"
      }

      {reason, ctx} = Error.with_context(:permission_denied, context)

      assert reason == :permission_denied
      assert ctx.operation == :put
      assert ctx.path == "protected/file.txt"
      assert ctx.provider == :s3
      assert ctx.message == "Access Denied"
    end
  end

  describe "OBX004_1A_T4: Test not_found error with context" do
    test "not_found error can include operation context" do
      error =
        Error.with_context(:not_found, %{
          operation: :get,
          path: "missing.txt"
        })

      {reason, context} = error
      assert reason == :not_found
      assert context.operation == :get
      assert context.path == "missing.txt"
    end

    test "not_found is properly formatted with and without context" do
      assert Error.format_error(:not_found) == "Object not found"

      detailed = Error.with_context(:not_found, %{path: "test.txt"})
      assert Error.format_error(detailed) == "Object not found"
    end

    test "not_found is not retryable" do
      assert Error.retryable?(:not_found) == false

      detailed = Error.with_context(:not_found, %{path: "missing.txt"})
      assert Error.retryable?(detailed) == false
    end
  end

  describe "OBX004_1A_T5: Test permission_denied error with provider info" do
    test "permission_denied error can include provider information" do
      error =
        Error.with_context(:permission_denied, %{
          operation: :put,
          path: "protected/file.txt",
          provider: :s3,
          message: "Access Denied"
        })

      {reason, context} = error
      assert reason == :permission_denied
      assert context.provider == :s3
      assert context.message == "Access Denied"
    end

    test "permission_denied is properly formatted" do
      assert Error.format_error(:permission_denied) == "Permission denied"

      detailed =
        Error.with_context(:permission_denied, %{
          provider: :azure,
          message: "Unauthorized"
        })

      assert Error.format_error(detailed) == "Permission denied"
    end

    test "permission_denied is not retryable" do
      assert Error.retryable?(:permission_denied) == false

      detailed = Error.with_context(:permission_denied, %{provider: :s3})
      assert Error.retryable?(detailed) == false
    end
  end

  describe "OBX004_1A_T6: Test network errors are retryable" do
    test "network_error is retryable" do
      assert Error.retryable?(:network_error) == true
    end

    test "timeout is retryable" do
      assert Error.retryable?(:timeout) == true
    end

    test "network errors with context are retryable" do
      network_error = Error.with_context(:network_error, %{message: "Connection refused"})
      assert Error.retryable?(network_error) == true

      timeout_error = Error.with_context(:timeout, %{operation: :get})
      assert Error.retryable?(timeout_error) == true
    end

    test "network errors are properly formatted" do
      assert Error.format_error(:network_error) == "Network error"
      assert Error.format_error(:timeout) == "Operation timed out"
    end
  end

  describe "OBX004_1A_T7: Test all operations return consistent error format" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "get returns consistent error format", %{store: store} do
      result = ObjectStoreX.get(store, "nonexistent.txt")
      assert {:error, :not_found} = result
    end

    test "put with create mode returns consistent error format", %{store: store} do
      # First put succeeds
      assert {:ok, _meta} = ObjectStoreX.put(store, "file.txt", "data", mode: :create)

      # Second put with create mode returns already_exists
      result = ObjectStoreX.put(store, "file.txt", "new data", mode: :create)
      assert {:error, :already_exists} = result
    end

    test "get with if_match returns consistent error format", %{store: store} do
      :ok = ObjectStoreX.put(store, "file.txt", "data")

      # Get with wrong ETag
      result = ObjectStoreX.get(store, "file.txt", if_match: "wrong-etag")
      assert {:error, :precondition_failed} = result
    end

    test "get with if_none_match returns consistent error format", %{store: store} do
      :ok = ObjectStoreX.put(store, "file.txt", "data")
      {:ok, meta} = ObjectStoreX.head(store, "file.txt")

      # Get with matching ETag should return not_modified
      result = ObjectStoreX.get(store, "file.txt", if_none_match: meta.etag)
      assert {:error, :not_modified} = result
    end

    test "head returns consistent error format", %{store: store} do
      result = ObjectStoreX.head(store, "nonexistent.txt")
      assert {:error, :not_found} = result
    end

    test "copy returns consistent error format", %{store: store} do
      result = ObjectStoreX.copy(store, "nonexistent.txt", "destination.txt")
      assert {:error, :not_found} = result
    end

    test "all errors can be formatted consistently", %{store: store} do
      errors = [
        ObjectStoreX.get(store, "nonexistent.txt"),
        ObjectStoreX.head(store, "missing.txt"),
        ObjectStoreX.copy(store, "nonexistent.txt", "dest.txt")
      ]

      for {:error, reason} <- errors do
        message = Error.format_error(reason)
        assert is_binary(message)
        assert String.length(message) > 0
      end
    end
  end

  describe "Error mapping utility" do
    test "map_error converts string errors to atoms" do
      assert Error.map_error("not found") == :not_found
      assert Error.map_error("NotFound: The specified key does not exist") == :not_found
      assert Error.map_error("PermissionDenied: Access Denied") == :permission_denied
      assert Error.map_error("timeout") == :timeout
      assert Error.map_error("network error") == :network_error
      assert Error.map_error("already exists") == :already_exists
      assert Error.map_error("precondition failed") == :precondition_failed
      assert Error.map_error("not modified") == :not_modified
      assert Error.map_error("not supported") == :not_supported
      assert Error.map_error("invalid input") == :invalid_input
    end

    test "map_error handles case-insensitive matching" do
      assert Error.map_error("NOT FOUND") == :not_found
      assert Error.map_error("Permission Denied") == :permission_denied
      assert Error.map_error("TIMEOUT") == :timeout
    end

    test "map_error handles partial matches" do
      assert Error.map_error("Error: No such file or directory") == :not_found
      assert Error.map_error("Connection refused") == :network_error
      assert Error.map_error("Request timeout") == :timeout
      assert Error.map_error("Access denied by policy") == :permission_denied
    end

    test "map_error returns unknown for unrecognized errors" do
      assert {:unknown, "something weird"} = Error.map_error("something weird")
      assert {:unknown, "random error"} = Error.map_error("random error")
    end

    test "map_error preserves known error atoms" do
      assert Error.map_error(:not_found) == :not_found
      assert Error.map_error(:timeout) == :timeout
      assert Error.map_error(:network_error) == :network_error
    end
  end
end
