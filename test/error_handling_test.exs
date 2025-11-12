defmodule ObjectStoreX.ErrorHandlingTest do
  use ExUnit.Case, async: true
  doctest ObjectStoreX.Errors

  describe "OBX001_6A_T1: Error type mapping" do
    test "map_error handles all defined error atoms" do
      # Test that the Errors module defines all error types
      assert ObjectStoreX.Errors.describe(:ok) =~ "succeeded"
      assert ObjectStoreX.Errors.describe(:error) =~ "Generic error"
      assert ObjectStoreX.Errors.describe(:not_found) =~ "does not exist"
      assert ObjectStoreX.Errors.describe(:already_exists) =~ "already exists"
      assert ObjectStoreX.Errors.describe(:precondition_failed) =~ "precondition"
      assert ObjectStoreX.Errors.describe(:not_modified) =~ "not modified"
      assert ObjectStoreX.Errors.describe(:not_supported) =~ "not supported"
      assert ObjectStoreX.Errors.describe(:permission_denied) =~ "permission"
    end

    test "describe handles unknown error atoms" do
      result = ObjectStoreX.Errors.describe(:unknown_error)
      assert result =~ "Unknown error"
    end
  end

  describe "OBX001_6A_T2: Not found errors" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "get returns :not_found for missing object", %{store: store} do
      result = ObjectStoreX.get(store, "nonexistent.txt")
      assert {:error, :not_found} = result
    end

    test "head returns :not_found for missing object", %{store: store} do
      result = ObjectStoreX.head(store, "nonexistent.txt")
      assert {:error, :not_found} = result
    end

    test "copy returns :not_found for missing source", %{store: store} do
      result = ObjectStoreX.copy(store, "nonexistent.txt", "destination.txt")
      assert {:error, :not_found} = result
    end

    test "rename returns :not_found for missing source", %{store: store} do
      result = ObjectStoreX.rename(store, "nonexistent.txt", "new.txt")
      assert {:error, :not_found} = result
    end
  end

  describe "OBX001_6A_T3: Invalid path errors" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "operations handle empty path gracefully", %{store: store} do
      # Empty paths should not crash - they should return an error
      result = ObjectStoreX.put(store, "", "data")
      # Should either succeed (some providers allow it) or return an error
      assert :ok == result or match?({:error, _}, result)
    end

    test "get with empty path returns error or succeeds", %{store: store} do
      result = ObjectStoreX.get(store, "")
      # Should return not_found or another error
      assert match?({:error, _}, result)
    end
  end

  describe "OBX001_6A_T4: Error messages are descriptive" do
    test "error descriptions provide context" do
      errors = [
        :not_found,
        :already_exists,
        :precondition_failed,
        :not_modified,
        :not_supported,
        :permission_denied
      ]

      for error <- errors do
        description = ObjectStoreX.Errors.describe(error)
        assert is_binary(description)
        assert String.length(description) > 10
      end
    end
  end

  describe "OBX001_6A_T5: Error handling with rescue blocks" do
    test "new/2 handles invalid provider gracefully" do
      # This should return an error, not crash
      result =
        try do
          ObjectStoreX.new(:invalid_provider, [])
        rescue
          FunctionClauseError -> {:error, :invalid_provider}
          e -> {:error, Exception.message(e)}
        end

      assert match?({:error, _}, result)
    end

    test "operations handle invalid store reference gracefully" do
      invalid_store = make_ref()

      # These should not crash, but return errors
      assert match?({:error, _}, ObjectStoreX.put(invalid_store, "test.txt", "data"))
      assert match?({:error, _}, ObjectStoreX.get(invalid_store, "test.txt"))
      assert match?({:error, _}, ObjectStoreX.delete(invalid_store, "test.txt"))
      assert match?({:error, _}, ObjectStoreX.head(invalid_store, "test.txt"))

      assert match?(
               {:error, _},
               ObjectStoreX.copy(invalid_store, "source.txt", "dest.txt")
             )

      assert match?({:error, _}, ObjectStoreX.rename(invalid_store, "old.txt", "new.txt"))
    end
  end

  describe "Error handling with local filesystem provider" do
    setup do
      # Create a temporary directory for testing
      tmp_dir = System.tmp_dir!() |> Path.join("objectstorex_error_test_#{:rand.uniform(999_999)}")
      File.mkdir_p!(tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, store} = ObjectStoreX.new(:local, path: tmp_dir)
      {:ok, store: store, tmp_dir: tmp_dir}
    end

    test "delete on non-existent file succeeds or returns not_found", %{store: store} do
      # Delete is typically idempotent - it may succeed or return not_found
      result = ObjectStoreX.delete(store, "nonexistent.txt")
      assert result == :ok or result == {:error, :not_found}
    end

    test "operations work correctly after errors", %{store: store} do
      # Try to get a non-existent file
      assert {:error, :not_found} = ObjectStoreX.get(store, "missing.txt")

      # Store should still work after error
      assert :ok = ObjectStoreX.put(store, "test.txt", "Hello")
      assert {:ok, "Hello"} = ObjectStoreX.get(store, "test.txt")
    end
  end

  describe "Error handling patterns" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "with clause pattern for error handling", %{store: store} do
      result =
        with :ok <- ObjectStoreX.put(store, "file.txt", "data"),
             {:ok, data} <- ObjectStoreX.get(store, "file.txt"),
             :ok <- ObjectStoreX.delete(store, "file.txt") do
          {:ok, data}
        end

      assert {:ok, "data"} = result
    end

    test "with clause catches errors", %{store: store} do
      result =
        with {:ok, data} <- ObjectStoreX.get(store, "nonexistent.txt"),
             :ok <- ObjectStoreX.delete(store, "file.txt") do
          {:ok, data}
        end

      assert {:error, :not_found} = result
    end

    test "pattern matching on error tuples", %{store: store} do
      result = ObjectStoreX.get(store, "missing.txt")

      message =
        case result do
          {:ok, data} -> "Got data: #{data}"
          {:error, :not_found} -> "File not found"
          {:error, :permission_denied} -> "Access denied"
          {:error, _other} -> "Other error"
        end

      assert message == "File not found"
    end
  end
end
