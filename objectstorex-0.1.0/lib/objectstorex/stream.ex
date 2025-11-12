defmodule ObjectStoreX.Stream do
  @moduledoc """
  Streaming operations for large files.

  This module provides streaming download capabilities that allow you to process
  large files without loading them entirely into memory.

  ## Examples

      # Download a large file and write to disk
      stream = ObjectStoreX.Stream.download(store, "large-file.bin")

      File.open!("output.bin", [:write], fn file ->
        stream
        |> Stream.each(&IO.binwrite(file, &1))
        |> Stream.run()
      end)

      # Process chunks
      total_bytes =
        stream
        |> Stream.map(&byte_size/1)
        |> Enum.sum()

  """

  alias ObjectStoreX.Native

  @type store :: reference()
  @type path :: String.t()

  @doc """
  Create an Elixir Stream for downloading a large object.

  The stream will emit binary chunks as they are received from the object store.
  The chunks are yielded in order and the stream completes when the entire object
  has been downloaded.

  ## Options

  * `:timeout` - Timeout in milliseconds for receiving each chunk (default: 30_000)

  ## Examples

      stream = ObjectStoreX.Stream.download(store, "large-file.bin")

      # Write to file
      File.open!("output.bin", [:write], fn file ->
        stream |> Stream.each(&IO.binwrite(file, &1)) |> Stream.run()
      end)

      # Count bytes
      total_bytes = stream |> Stream.map(&byte_size/1) |> Enum.sum()

  ## Error Handling

  If an error occurs during streaming, the stream will raise an exception.
  """
  @spec download(store(), path(), keyword()) :: Enumerable.t()
  def download(store, path, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 30_000)

    Stream.resource(
      fn -> start_download(store, path) end,
      fn stream_id -> receive_chunk(stream_id, timeout) end,
      fn stream_id -> cleanup_download(stream_id) end
    )
  end

  # Start the download stream by calling the NIF
  defp start_download(store, path) do
    case Native.start_download_stream(store, path, self()) do
      {:ok, stream_id} ->
        stream_id

      {:error, reason} ->
        raise "Download stream failed to start: #{inspect(reason)}"
    end
  end

  # Receive a chunk from the stream
  defp receive_chunk(stream_id, timeout) do
    receive do
      {:chunk, ^stream_id, data} ->
        # Return the chunk and continue with the stream_id
        {[data], stream_id}

      {:done, ^stream_id} ->
        # Stream is complete
        {:halt, stream_id}

      {:error, ^stream_id, reason} ->
        # Error occurred, raise exception
        raise "Stream error: #{reason}"
    after
      timeout ->
        raise "Stream timeout after #{timeout}ms"
    end
  end

  # Clean up the download stream
  defp cleanup_download(stream_id) do
    # Cancel the stream on the Rust side
    Native.cancel_download_stream(stream_id)
    :ok
  end

  @doc """
  Upload a large file using streaming multipart upload.

  The function consumes an Elixir Stream and uploads its data in chunks,
  using multipart upload behind the scenes. This allows uploading large files
  without loading them entirely into memory.

  ## Options

  None currently supported.

  ## Examples

      # Upload from file stream
      File.stream!("large-file.bin", [], 10_485_760)  # 10MB chunks
      |> ObjectStoreX.Stream.upload(store, "destination.bin")

      # Upload from generated data
      Stream.repeatedly(fn -> :crypto.strong_rand_bytes(1024) end)
      |> Stream.take(10_000)  # ~10MB total
      |> ObjectStoreX.Stream.upload(store, "random.dat")

  ## Error Handling

  If an error occurs during upload, the multipart upload will be aborted
  automatically and an error tuple will be returned.
  """
  @spec upload(Enumerable.t(), store(), path(), keyword()) :: :ok | {:error, term()}
  def upload(stream, store, path, _opts \\ []) do
    case Native.start_upload_session(store, path) do
      {:ok, session} ->
        try do
          # Consume the stream and upload chunks
          stream
          |> Stream.each(fn chunk ->
            case Native.upload_chunk(session, chunk) do
              :ok ->
                :ok

              {:error, reason} ->
                throw({:upload_error, reason})
            end
          end)
          |> Stream.run()

          # Complete the upload
          case Native.complete_upload(session) do
            :ok -> :ok
            {:error, reason} -> {:error, reason}
          end
        catch
          {:upload_error, reason} ->
            # Abort the upload on error
            Native.abort_upload(session)
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  List objects as a stream with automatic pagination.

  Returns a stream that yields object metadata maps. The stream automatically
  handles pagination and will continue until all objects matching the prefix
  have been returned.

  ## Options

  * `:prefix` - Optional prefix to filter objects (default: nil, lists all objects)
  * `:timeout` - Timeout in milliseconds for receiving each object (default: 30_000)

  ## Examples

      # List all objects with prefix
      ObjectStoreX.Stream.list_stream(store, prefix: "data/2025/")
      |> Stream.map(& &1.location)
      |> Enum.take(100)

      # Filter by size
      ObjectStoreX.Stream.list_stream(store, prefix: "logs/")
      |> Stream.filter(fn meta -> meta.size > 1_000_000 end)
      |> Stream.map(& &1.location)
      |> Enum.to_list()

      # Process in batches
      ObjectStoreX.Stream.list_stream(store)
      |> Stream.chunk_every(100)
      |> Stream.each(&process_batch/1)
      |> Stream.run()

  ## Metadata Structure

  Each object metadata map contains:

  * `:location` - String path of the object
  * `:size` - Size in bytes
  * `:last_modified` - ISO8601 timestamp string
  * `:etag` - Optional ETag string
  * `:version` - Optional version string

  ## Error Handling

  If an error occurs during listing, the stream will raise an exception.
  """
  @spec list_stream(store(), keyword()) :: Enumerable.t()
  def list_stream(store, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)
    timeout = Keyword.get(opts, :timeout, 30_000)

    Stream.resource(
      fn -> start_list(store, prefix) end,
      fn list_id -> receive_object(list_id, timeout) end,
      fn _list_id -> :ok end
    )
  end

  # Start the list stream by calling the NIF
  defp start_list(store, prefix) do
    case Native.start_list_stream(store, prefix, self()) do
      {:ok, list_id} ->
        list_id

      {:error, reason} ->
        raise "List stream failed to start: #{inspect(reason)}"
    end
  end

  # Receive an object metadata from the stream
  defp receive_object(list_id, timeout) do
    receive do
      {:object, ^list_id, meta} ->
        # Return the metadata and continue with the list_id
        {[meta], list_id}

      {:done, ^list_id} ->
        # Stream is complete
        {:halt, list_id}

      {:error, ^list_id, reason} ->
        # Error occurred, raise exception
        raise "List stream error: #{reason}"
    after
      timeout ->
        raise "List stream timeout after #{timeout}ms"
    end
  end
end
