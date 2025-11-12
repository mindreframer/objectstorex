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
end
