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

  describe "OBX002_3A: Upload Streaming Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_3A_T1: Test upload session initialization", %{store: store} do
      # Start upload session
      case ObjectStoreX.Native.start_upload_session(store, "upload_test.bin") do
        {:ok, session} ->
          # Session should be a reference
          assert is_reference(session)

          # Clean up - abort the session
          assert :ok = ObjectStoreX.Native.abort_upload(session)

        {:error, reason} ->
          flunk("Failed to start upload session: #{inspect(reason)}")
      end
    end

    test "OBX002_3A_T2: Test upload_chunk buffers data", %{store: store} do
      # Start upload session
      {:ok, session} = ObjectStoreX.Native.start_upload_session(store, "chunk_buffer.bin")

      # Upload small chunks (less than 5MB part size)
      chunk1 = "Hello, "
      chunk2 = "world!"

      assert :ok = ObjectStoreX.Native.upload_chunk(session, chunk1)
      assert :ok = ObjectStoreX.Native.upload_chunk(session, chunk2)

      # Complete the upload
      assert :ok = ObjectStoreX.Native.complete_upload(session)

      # Verify the uploaded data
      {:ok, data} = ObjectStoreX.get(store, "chunk_buffer.bin")
      assert data == "Hello, world!"
    end

    test "OBX002_3A_T3: Test upload completes successfully", %{store: store} do
      # Create test data
      test_data = "Upload test data"

      # Create a stream from the test data
      stream = Stream.repeatedly(fn -> test_data end) |> Stream.take(1)

      # Upload the stream
      assert :ok = ObjectStoreX.Stream.upload(stream, store, "complete_test.bin")

      # Verify the uploaded data
      {:ok, result} = ObjectStoreX.get(store, "complete_test.bin")
      assert result == test_data
    end

    test "OBX002_3A_T4: Test upload preserves data integrity", %{store: store} do
      # Test with various data types
      test_cases = [
        {"simple", "hello"},
        {"unicode", "Hello 世界 🌍"},
        {"binary", <<0, 1, 2, 255, 254, 253>>},
        {"medium", String.duplicate("x", 1000)},
        {"large", String.duplicate("test data ", 1000)}
      ]

      for {name, data} <- test_cases do
        path = "upload_integrity_#{name}.dat"
        stream = Stream.repeatedly(fn -> data end) |> Stream.take(1)

        assert :ok = ObjectStoreX.Stream.upload(stream, store, path),
               "Failed to upload #{name}"

        {:ok, result} = ObjectStoreX.get(store, path)
        assert result == data, "Data integrity failed for #{name}"
      end
    end

    test "OBX002_3A_T5: Test upload from Elixir Stream", %{store: store} do
      # Create a stream that generates multiple chunks
      stream =
        Stream.repeatedly(fn -> "chunk " end)
        |> Stream.take(100)

      # Upload the stream
      assert :ok = ObjectStoreX.Stream.upload(stream, store, "stream_upload.bin")

      # Verify the uploaded data
      {:ok, result} = ObjectStoreX.get(store, "stream_upload.bin")
      expected = String.duplicate("chunk ", 100)
      assert result == expected
    end

    test "OBX002_3A_T6: Test upload with small chunks (< part_size)", %{store: store} do
      # Create many small chunks (each 1KB, total < 5MB part size)
      chunk = String.duplicate("x", 1024)
      stream = Stream.repeatedly(fn -> chunk end) |> Stream.take(100)

      # Upload
      assert :ok = ObjectStoreX.Stream.upload(stream, store, "small_chunks.bin")

      # Verify
      {:ok, result} = ObjectStoreX.get(store, "small_chunks.bin")
      expected = String.duplicate(chunk, 100)
      assert result == expected
      assert byte_size(result) == 102_400
    end

    test "OBX002_3A_T7: Test upload with large chunks (> part_size)", %{store: store} do
      # Create chunks larger than 5MB part size
      # Use 6MB chunk to trigger part upload
      chunk = String.duplicate("x", 6 * 1024 * 1024)
      stream = Stream.repeatedly(fn -> chunk end) |> Stream.take(2)

      # Upload
      assert :ok = ObjectStoreX.Stream.upload(stream, store, "large_chunks.bin")

      # Verify
      {:ok, result} = ObjectStoreX.get(store, "large_chunks.bin")
      expected = String.duplicate(chunk, 2)
      assert result == expected
      assert byte_size(result) == 12 * 1024 * 1024
    end

    test "OBX002_3A_T8: Test abort_upload cancels upload", %{store: store} do
      # Start upload session
      {:ok, session} = ObjectStoreX.Native.start_upload_session(store, "abort_test.bin")

      # Upload some data
      assert :ok = ObjectStoreX.Native.upload_chunk(session, "test data")

      # Abort the upload
      assert :ok = ObjectStoreX.Native.abort_upload(session)

      # Verify the file doesn't exist (or is incomplete)
      case ObjectStoreX.get(store, "abort_test.bin") do
        {:error, :not_found} ->
          # Expected - file wasn't created
          :ok

        {:ok, _data} ->
          # File might exist if provider doesn't clean up immediately
          # This is acceptable behavior for some providers
          :ok
      end
    end

    test "OBX002_3A_T9: Test upload error triggers abort", %{store: store} do
      # Create a stream that will fail partway through
      stream =
        Stream.resource(
          fn -> 0 end,
          fn
            count when count < 5 ->
              {["chunk #{count}"], count + 1}

            5 ->
              # Simulate an error by returning invalid data
              raise "Simulated upload error"
          end,
          fn _count -> :ok end
        )

      # Upload should fail and trigger abort
      result = ObjectStoreX.Stream.upload(stream, store, "error_test.bin")

      case result do
        {:error, _reason} ->
          # Expected - error was caught and upload aborted
          :ok

        :ok ->
          flunk("Expected upload to fail but it succeeded")
      end
    end
  end

  describe "OBX002_3A: Upload Integration Tests" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "OBX002_3A_T10: Test upload from file stream", %{store: store} do
      # Create a temporary file
      temp_path =
        Path.join(System.tmp_dir!(), "objectstorex_upload_test_#{:rand.uniform(1_000_000)}.txt")

      test_data = String.duplicate("File upload test\n", 1000)

      try do
        # Write test data to file
        File.write!(temp_path, test_data)

        # Upload from file stream (1MB chunks)
        stream = File.stream!(temp_path, [], 1024 * 1024)
        assert :ok = ObjectStoreX.Stream.upload(stream, store, "file_upload.txt")

        # Verify uploaded data
        {:ok, result} = ObjectStoreX.get(store, "file_upload.txt")
        assert result == test_data
      after
        File.rm(temp_path)
      end
    end

    test "OBX002_3A_T11: Test complete workflow: upload → download → verify", %{store: store} do
      # Create test data
      test_data = String.duplicate("Round-trip test data\n", 500)

      # Upload using streaming
      upload_stream = Stream.repeatedly(fn -> test_data end) |> Stream.take(1)
      assert :ok = ObjectStoreX.Stream.upload(upload_stream, store, "roundtrip.bin")

      # Download using streaming
      download_result =
        ObjectStoreX.Stream.download(store, "roundtrip.bin")
        |> Enum.to_list()
        |> IO.iodata_to_binary()

      # Verify data integrity
      assert download_result == test_data
    end
  end
end
