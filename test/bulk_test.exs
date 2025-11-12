defmodule BulkTest do
  use ExUnit.Case

  describe "OBX002_4A: Bulk Delete Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_4A_T1: Test delete_many with multiple objects", %{store: store} do
      # Create multiple test files
      paths = ["file1.txt", "file2.txt", "file3.txt"]

      for path <- paths do
        assert :ok = ObjectStoreX.put(store, path, "test data")
      end

      # Verify files exist
      for path <- paths do
        assert {:ok, _} = ObjectStoreX.get(store, path)
      end

      # Delete all files
      assert {:ok, succeeded, failed} = ObjectStoreX.delete_many(store, paths)
      assert succeeded == 3
      assert failed == []

      # Verify files are deleted
      for path <- paths do
        assert {:error, :not_found} = ObjectStoreX.get(store, path)
      end
    end

    test "OBX002_4A_T2: Test delete_many returns correct count", %{store: store} do
      # Create 10 test files
      paths = for i <- 1..10, do: "count_test_#{i}.txt"

      for path <- paths do
        assert :ok = ObjectStoreX.put(store, path, "data #{path}")
      end

      # Delete all files
      assert {:ok, succeeded, failed} = ObjectStoreX.delete_many(store, paths)
      assert succeeded == 10
      assert failed == []
    end

    test "OBX002_4A_T3: Test delete_many with empty list", %{store: store} do
      # Delete with empty list should succeed with 0 count
      assert {:ok, succeeded, failed} = ObjectStoreX.delete_many(store, [])
      assert succeeded == 0
      assert failed == []
    end

    test "OBX002_4A_T4: Test delete_many handles partial failures", %{store: store} do
      # Create some files but not others
      existing_paths = ["exists1.txt", "exists2.txt"]
      non_existing_paths = ["does_not_exist1.txt", "does_not_exist2.txt"]

      for path <- existing_paths do
        assert :ok = ObjectStoreX.put(store, path, "data")
      end

      # Try to delete both existing and non-existing files
      all_paths = existing_paths ++ non_existing_paths

      # Note: object_store's delete_stream continues on errors
      # Non-existing files may or may not cause failures depending on provider
      # For memory provider, deleting non-existing files typically succeeds (idempotent)
      {:ok, _succeeded, _failed} = ObjectStoreX.delete_many(store, all_paths)

      # Verify existing files are deleted
      for path <- existing_paths do
        assert {:error, :not_found} = ObjectStoreX.get(store, path)
      end
    end

    test "OBX002_4A_T5: Test delete_many with 100+ objects", %{store: store} do
      # Create 150 test files to test batching behavior
      paths = for i <- 1..150, do: "bulk_#{i}.txt"

      for path <- paths do
        assert :ok = ObjectStoreX.put(store, path, "data")
      end

      # Delete all 150 files
      assert {:ok, succeeded, failed} = ObjectStoreX.delete_many(store, paths)
      assert succeeded == 150
      assert failed == []

      # Verify all files are deleted
      for path <- paths do
        assert {:error, :not_found} = ObjectStoreX.get(store, path)
      end
    end

    test "OBX002_4A_T6: Test delete_many removes all objects", %{store: store} do
      # Create files with various names
      paths = [
        "data/2024/file1.txt",
        "data/2024/file2.txt",
        "logs/app.log",
        "config.json",
        "README.md"
      ]

      for path <- paths do
        assert :ok = ObjectStoreX.put(store, path, "content for #{path}")
      end

      # Verify all exist
      for path <- paths do
        assert {:ok, _} = ObjectStoreX.get(store, path)
      end

      # Delete all
      assert {:ok, succeeded, failed} = ObjectStoreX.delete_many(store, paths)
      assert succeeded == length(paths)
      assert failed == []

      # Verify all deleted
      for path <- paths do
        assert {:error, :not_found} = ObjectStoreX.get(store, path)
      end
    end
  end
end
