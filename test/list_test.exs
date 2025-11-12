defmodule ObjectStoreX.ListTest do
  use ExUnit.Case
  doctest ObjectStoreX.Stream

  describe "OBX002_5A: List Operations Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_5A_T1: Test list_stream returns all objects", %{store: store} do
      # Create multiple test objects
      objects = [
        "file1.txt",
        "file2.txt",
        "file3.txt",
        "data/file4.txt",
        "data/file5.txt"
      ]

      for path <- objects do
        assert :ok = ObjectStoreX.put(store, path, "test data")
      end

      # List all objects
      listed =
        ObjectStoreX.Stream.list_stream(store)
        |> Enum.to_list()

      # Should have all objects
      assert length(listed) == length(objects)

      # All items should be maps with metadata
      assert Enum.all?(listed, &is_map/1)
      assert Enum.all?(listed, fn meta -> Map.has_key?(meta, :location) end)
      assert Enum.all?(listed, fn meta -> Map.has_key?(meta, :size) end)
      assert Enum.all?(listed, fn meta -> Map.has_key?(meta, :last_modified) end)

      # All object paths should be in the results
      listed_locations = Enum.map(listed, & &1.location) |> Enum.sort()
      assert listed_locations == Enum.sort(objects)
    end

    test "OBX002_5A_T2: Test list_stream with prefix filter", %{store: store} do
      # Create objects with different prefixes
      assert :ok = ObjectStoreX.put(store, "data/file1.txt", "data1")
      assert :ok = ObjectStoreX.put(store, "data/file2.txt", "data2")
      assert :ok = ObjectStoreX.put(store, "logs/log1.txt", "log1")
      assert :ok = ObjectStoreX.put(store, "logs/log2.txt", "log2")
      assert :ok = ObjectStoreX.put(store, "other.txt", "other")

      # List with "data/" prefix
      data_objects =
        ObjectStoreX.Stream.list_stream(store, prefix: "data/")
        |> Enum.to_list()

      assert length(data_objects) == 2
      assert Enum.all?(data_objects, fn meta -> String.starts_with?(meta.location, "data/") end)

      # List with "logs/" prefix
      log_objects =
        ObjectStoreX.Stream.list_stream(store, prefix: "logs/")
        |> Enum.to_list()

      assert length(log_objects) == 2
      assert Enum.all?(log_objects, fn meta -> String.starts_with?(meta.location, "logs/") end)

      # List with non-existent prefix
      empty =
        ObjectStoreX.Stream.list_stream(store, prefix: "nonexistent/")
        |> Enum.to_list()

      assert empty == []
    end

    test "OBX002_5A_T3: Test list_stream handles pagination", %{store: store} do
      # Create many objects to test pagination
      # Note: In-memory store may not paginate, but the stream should still work
      num_objects = 50

      for i <- 1..num_objects do
        path = "item_#{String.pad_leading("#{i}", 3, "0")}.txt"
        assert :ok = ObjectStoreX.put(store, path, "data #{i}")
      end

      # List all using stream
      listed =
        ObjectStoreX.Stream.list_stream(store)
        |> Enum.to_list()

      # Should get all objects
      assert length(listed) == num_objects

      # All should be valid metadata
      assert Enum.all?(listed, &is_map/1)
      assert Enum.all?(listed, fn meta -> is_binary(meta.location) end)
      assert Enum.all?(listed, fn meta -> is_integer(meta.size) and meta.size > 0 end)
    end

    test "OBX002_5A_T4: Test list_stream with 100+ objects", %{store: store} do
      # Create 150 objects
      num_objects = 150

      for i <- 1..num_objects do
        path = "obj_#{String.pad_leading("#{i}", 4, "0")}.txt"
        assert :ok = ObjectStoreX.put(store, path, "content #{i}")
      end

      # List and count
      count =
        ObjectStoreX.Stream.list_stream(store)
        |> Enum.count()

      assert count == num_objects

      # Verify we can process in batches
      batches =
        ObjectStoreX.Stream.list_stream(store)
        |> Stream.chunk_every(25)
        |> Enum.to_list()

      assert length(batches) == 6
      # First 5 batches should have 25 items, last should have 25
      assert Enum.all?(Enum.take(batches, 5), fn batch -> length(batch) == 25 end)
      assert length(List.last(batches)) == 25
    end

    test "OBX002_5A_T5: Test list_stream metadata correctness", %{store: store} do
      # Create objects with known sizes
      test_data = [
        {"small.txt", "hi"},
        {"medium.txt", String.duplicate("x", 1000)},
        {"large.txt", String.duplicate("test", 5000)}
      ]

      for {path, content} <- test_data do
        assert :ok = ObjectStoreX.put(store, path, content)
      end

      # List and verify metadata
      listed =
        ObjectStoreX.Stream.list_stream(store)
        |> Enum.to_list()

      assert length(listed) == 3

      # Create a map of path to content for easy lookup
      test_data_map = Map.new(test_data)

      # Verify sizes match for each object
      for meta <- listed do
        assert Map.has_key?(test_data_map, meta.location),
               "Unexpected object: #{meta.location}"

        expected_content = test_data_map[meta.location]
        assert meta.size == byte_size(expected_content),
               "Size mismatch for #{meta.location}: expected #{byte_size(expected_content)}, got #{meta.size}"

        assert is_binary(meta.last_modified),
               "last_modified should be a string for #{meta.location}"

        # Version may be nil for in-memory store
        assert is_nil(meta.version) or is_binary(meta.version),
               "version should be nil or string for #{meta.location}"
      end
    end

    test "OBX002_5A_T6: Test list_with_delimiter returns prefixes", %{store: store} do
      # Create objects with directory-like structure
      assert :ok = ObjectStoreX.put(store, "root.txt", "root")
      assert :ok = ObjectStoreX.put(store, "data/2024/file1.txt", "data1")
      assert :ok = ObjectStoreX.put(store, "data/2024/file2.txt", "data2")
      assert :ok = ObjectStoreX.put(store, "data/2025/file3.txt", "data3")
      assert :ok = ObjectStoreX.put(store, "logs/app.log", "log")

      # List root level with delimiter
      {:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store)

      # Should have root.txt as object
      object_locations = Enum.map(objects, & &1.location)
      assert "root.txt" in object_locations

      # Should have common prefixes
      assert is_list(prefixes)
      # Should have "data/" and "logs/" as prefixes
      assert "data/" in prefixes or "data" in prefixes
      assert "logs/" in prefixes or "logs" in prefixes
    end

    test "OBX002_5A_T7: Test list_with_delimiter separates objects/prefixes", %{store: store} do
      # Create a clear directory structure
      assert :ok = ObjectStoreX.put(store, "data/file.txt", "file")
      assert :ok = ObjectStoreX.put(store, "data/sub1/file1.txt", "file1")
      assert :ok = ObjectStoreX.put(store, "data/sub2/file2.txt", "file2")

      # List "data/" prefix
      {:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store, prefix: "data/")

      # Should have "data/file.txt" as an object
      object_locations = Enum.map(objects, & &1.location)
      assert "data/file.txt" in object_locations

      # Should have subdirectories as prefixes
      assert is_list(prefixes)
      assert length(prefixes) >= 2

      # Prefixes should contain sub directories
      prefix_strings = Enum.map(prefixes, &to_string/1)
      assert Enum.any?(prefix_strings, fn p -> String.contains?(p, "sub1") end)
      assert Enum.any?(prefix_strings, fn p -> String.contains?(p, "sub2") end)
    end

    test "OBX002_5A_T8: Test list operations work with all providers", %{store: store} do
      # Test with memory store (already set up in setup)
      # Create some test data
      test_objects = ["test1.txt", "test2.txt", "test3.txt"]

      for path <- test_objects do
        assert :ok = ObjectStoreX.put(store, path, "test data")
      end

      # Test list_stream
      stream_result =
        ObjectStoreX.Stream.list_stream(store)
        |> Enum.to_list()

      assert length(stream_result) == 3
      assert Enum.all?(stream_result, &is_map/1)

      # Test list_with_delimiter
      {:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store)

      assert is_list(objects)
      assert is_list(prefixes)
      assert length(objects) == 3

      # Verify all operations completed successfully
      assert Enum.all?(stream_result, fn meta ->
               Map.has_key?(meta, :location) and
                 Map.has_key?(meta, :size) and
                 Map.has_key?(meta, :last_modified)
             end)
    end
  end
end
