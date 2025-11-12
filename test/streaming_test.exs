defmodule ObjectStoreX.StreamingTest do
  use ExUnit.Case
  doctest ObjectStoreX.Stream

  describe "OBX002_1A: Download Streaming Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_1A_T1: Test download stream returns chunks", %{store: store} do
      # Put some test data
      test_data = "Hello, streaming world!"
      assert :ok = ObjectStoreX.put(store, "test.txt", test_data)

      # Download as stream and collect chunks
      chunks =
        ObjectStoreX.Stream.download(store, "test.txt")
        |> Enum.to_list()

      # Should have at least one chunk
      assert length(chunks) > 0

      # All chunks should be binaries
      assert Enum.all?(chunks, &is_binary/1)

      # Concatenated chunks should equal original data
      result = IO.iodata_to_binary(chunks)
      assert result == test_data
    end

    test "OBX002_1A_T2: Test download stream completes with :done", %{store: store} do
      # Put test data
      test_data = "Stream completion test"
      assert :ok = ObjectStoreX.put(store, "complete.txt", test_data)

      # Download and verify stream completes without error
      assert_receive_eventually = fn ->
        result =
          ObjectStoreX.Stream.download(store, "complete.txt")
          |> Enum.to_list()
          |> IO.iodata_to_binary()

        assert result == test_data
      end

      # Should complete without raising
      assert_receive_eventually.()
    end

    test "OBX002_1A_T3: Test download preserves data integrity", %{store: store} do
      # Test with various data types
      test_cases = [
        {"simple", "hello"},
        {"unicode", "Hello 世界 🌍"},
        {"binary", <<0, 1, 2, 255, 254, 253>>},
        {"empty", ""},
        {"medium", String.duplicate("x", 1000)},
        {"large", String.duplicate("test data ", 10000)}
      ]

      for {name, data} <- test_cases do
        path = "integrity_#{name}.dat"
        assert :ok = ObjectStoreX.put(store, path, data), "Failed to put #{name}"

        result =
          ObjectStoreX.Stream.download(store, path)
          |> Enum.to_list()
          |> IO.iodata_to_binary()

        assert result == data, "Data integrity failed for #{name}"
      end
    end

    test "OBX002_1A_T4: Test download stream can be consumed by Enum", %{store: store} do
      # Put test data
      test_data = "Enumerable test"
      assert :ok = ObjectStoreX.put(store, "enum.txt", test_data)

      stream = ObjectStoreX.Stream.download(store, "enum.txt")

      # Test various Enum operations
      # Count chunks
      chunk_count = stream |> Enum.count()
      assert chunk_count > 0

      # Get first chunk
      first = stream |> Enum.take(1) |> List.first()
      assert is_binary(first)

      # Map over chunks
      byte_sizes = stream |> Enum.map(&byte_size/1)
      assert Enum.all?(byte_sizes, &(&1 > 0))

      # Sum total bytes
      total_bytes = stream |> Enum.map(&byte_size/1) |> Enum.sum()
      assert total_bytes == byte_size(test_data)
    end

    test "OBX002_1A_T5: Test download stream timeout handling", %{store: store} do
      # Put test data
      test_data = "Timeout test"
      assert :ok = ObjectStoreX.put(store, "timeout.txt", test_data)

      # Download with very short timeout - should still work for small files
      result =
        ObjectStoreX.Stream.download(store, "timeout.txt", timeout: 100)
        |> Enum.to_list()
        |> IO.iodata_to_binary()

      assert result == test_data
    end

    test "OBX002_1A_T6: Test download stream error propagation", %{store: store} do
      # Try to download non-existent file
      assert_raise RuntimeError, ~r/Stream error/, fn ->
        ObjectStoreX.Stream.download(store, "nonexistent.txt")
        |> Enum.to_list()
      end
    end

    test "OBX002_1A_T7: Test cancel_download_stream stops streaming", %{store: store} do
      # Put a medium-sized file
      test_data = String.duplicate("x", 10000)
      assert :ok = ObjectStoreX.put(store, "cancel.txt", test_data)

      # Start streaming
      stream_pid = self()

      task =
        Task.async(fn ->
          # Start download
          case ObjectStoreX.Native.start_download_stream(store, "cancel.txt", stream_pid) do
            {:ok, stream_id} ->
              # Immediately cancel
              :ok = ObjectStoreX.Native.cancel_download_stream(stream_id)
              {:cancelled, stream_id}

            error ->
              error
          end
        end)

      # Should successfully cancel
      assert {:cancelled, _stream_id} = Task.await(task)

      # Flush any pending messages
      receive do
        _ -> :ok
      after
        100 -> :ok
      end
    end
  end

  describe "OBX002_1A: Stream Integration Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_1A_T8: Test streaming large file to disk", %{store: store} do
      # Create a larger test file
      test_data = String.duplicate("Large file test data\n", 1000)
      assert :ok = ObjectStoreX.put(store, "large.txt", test_data)

      # Create temp file
      temp_path = Path.join(System.tmp_dir!(), "objectstorex_test_#{:rand.uniform(1000000)}.txt")

      try do
        # Stream to file
        File.open!(temp_path, [:write], fn file ->
          ObjectStoreX.Stream.download(store, "large.txt")
          |> Stream.each(&IO.binwrite(file, &1))
          |> Stream.run()
        end)

        # Verify file contents
        {:ok, file_data} = File.read(temp_path)
        assert file_data == test_data
      after
        File.rm(temp_path)
      end
    end

    test "OBX002_1A_T9: Test concurrent streaming downloads", %{store: store} do
      # Create multiple test files
      for i <- 1..5 do
        data = "Concurrent test #{i}: " <> String.duplicate("data", 100)
        assert :ok = ObjectStoreX.put(store, "concurrent_#{i}.txt", data)
      end

      # Download all concurrently
      tasks =
        for i <- 1..5 do
          Task.async(fn ->
            result =
              ObjectStoreX.Stream.download(store, "concurrent_#{i}.txt")
              |> Enum.to_list()
              |> IO.iodata_to_binary()

            {i, result}
          end)
        end

      results = Task.await_many(tasks, 5000)

      # Verify all succeeded
      assert length(results) == 5

      for {i, result} <- results do
        expected = "Concurrent test #{i}: " <> String.duplicate("data", 100)
        assert result == expected
      end
    end

    test "OBX002_1A_T10: Test stream with Stream.chunk_every", %{store: store} do
      # Put test data
      test_data = String.duplicate("chunk test ", 100)
      assert :ok = ObjectStoreX.put(store, "chunk_every.txt", test_data)

      # Download and chunk by 10
      chunks =
        ObjectStoreX.Stream.download(store, "chunk_every.txt")
        |> Stream.chunk_every(10)
        |> Enum.to_list()

      # Should have chunked the stream
      assert is_list(chunks)

      # Flatten and verify data
      result =
        chunks
        |> List.flatten()
        |> IO.iodata_to_binary()

      assert result == test_data
    end
  end
end
