defmodule FileUploader do
  @moduledoc """
  Example: Large file uploader with progress tracking.

  This example demonstrates how to use ObjectStoreX to upload large files
  with progress tracking and efficient streaming.

  ## Features

  - Chunked file uploads with configurable chunk size
  - Progress tracking callback
  - Efficient memory usage (streaming, not loading entire file)
  - Support for all ObjectStoreX providers (S3, Azure, GCS, Local)

  ## Usage

      {:ok, store} = ObjectStoreX.new(:s3,
        bucket: "my-bucket",
        region: "us-east-1"
      )

      FileUploader.upload_file(store, "large-file.bin", "uploads/file.bin",
        chunk_size: 10_485_760,  # 10MB chunks
        on_progress: fn bytes_uploaded, total_size ->
          percentage = trunc(bytes_uploaded / total_size * 100)
          IO.puts("Progress: \#{bytes_uploaded}/\#{total_size} (\#{percentage}%)")
        end
      )

      FileUploader.download_file(store, "uploads/file.bin", "downloaded-file.bin",
        on_progress: fn bytes_downloaded, total_size ->
          percentage = trunc(bytes_downloaded / total_size * 100)
          IO.puts("Downloaded: \#{bytes_downloaded}/\#{total_size} (\#{percentage}%)")
        end
      )

  ## Example: Upload with progress bar

      defmodule ProgressBar do
        def start(total) do
          Agent.start_link(fn -> %{total: total, current: 0} end, name: __MODULE__)
        end

        def update(bytes, total) do
          percentage = trunc(bytes / total * 100)
          bar_length = 50
          filled = trunc(bar_length * bytes / total)
          bar = String.duplicate("=", filled) <> String.duplicate(" ", bar_length - filled)
          IO.write("\\r[\#{bar}] \#{percentage}%")
        end
      end

      {:ok, store} = ObjectStoreX.new(:local, root: "/tmp/uploads")

      FileUploader.upload_file(store, "large-file.bin", "file.bin",
        on_progress: &ProgressBar.update/2
      )
  """

  alias ObjectStoreX.Stream, as: StoreStream

  @doc """
  Upload a file to object storage with progress tracking.

  ## Options

  - `:chunk_size` - Size of each chunk in bytes (default: 10MB)
  - `:on_progress` - Callback function `(bytes_uploaded, total_size) -> any()`

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec upload_file(ObjectStoreX.store(), String.t(), String.t(), keyword()) ::
          :ok | {:error, atom()}
  def upload_file(store, local_path, remote_path, opts \\ []) do
    chunk_size = Keyword.get(opts, :chunk_size, 10_485_760)
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    with {:ok, stat} <- File.stat(local_path),
         file_size = stat.size,
         stream <- build_upload_stream(local_path, chunk_size, file_size, on_progress),
         :ok <- StoreStream.upload(stream, store, remote_path) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Download a file from object storage with progress tracking.

  ## Options

  - `:on_progress` - Callback function `(bytes_downloaded, total_size) -> any()`

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec download_file(ObjectStoreX.store(), String.t(), String.t(), keyword()) ::
          :ok | {:error, atom()}
  def download_file(store, remote_path, local_path, opts \\ []) do
    on_progress = Keyword.get(opts, :on_progress, fn _, _ -> :ok end)

    with {:ok, stream, metadata} <- StoreStream.download(store, remote_path),
         total_size = metadata.size,
         :ok <- write_stream_to_file(stream, local_path, total_size, on_progress) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List all files in a directory with size information.

  ## Options

  - `:prefix` - Directory prefix to list

  ## Returns

  - Stream of file metadata

  ## Example

      FileUploader.list_files(store, prefix: "uploads/")
      |> Stream.each(fn meta ->
        IO.puts("\#{meta.location} - \#{format_size(meta.size)}")
      end)
      |> Stream.run()
  """
  @spec list_files(ObjectStoreX.store(), keyword()) :: Enumerable.t()
  def list_files(store, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, "")
    StoreStream.list_stream(store, prefix: prefix)
  end

  @doc """
  Format file size in human-readable format.

  ## Examples

      iex> FileUploader.format_size(1024)
      "1.00 KB"

      iex> FileUploader.format_size(1_048_576)
      "1.00 MB"

      iex> FileUploader.format_size(1_073_741_824)
      "1.00 GB"
  """
  @spec format_size(non_neg_integer()) :: String.t()
  def format_size(bytes) when bytes < 1024, do: "#{bytes} B"

  def format_size(bytes) when bytes < 1_048_576,
    do: :erlang.float_to_binary(bytes / 1024, decimals: 2) <> " KB"

  def format_size(bytes) when bytes < 1_073_741_824,
    do: :erlang.float_to_binary(bytes / 1_048_576, decimals: 2) <> " MB"

  def format_size(bytes),
    do: :erlang.float_to_binary(bytes / 1_073_741_824, decimals: 2) <> " GB"

  # Private helpers

  defp build_upload_stream(local_path, chunk_size, file_size, on_progress) do
    File.stream!(local_path, [], chunk_size)
    |> Stream.with_index()
    |> Stream.map(fn {chunk, index} ->
      bytes_uploaded = min((index + 1) * chunk_size, file_size)
      on_progress.(bytes_uploaded, file_size)
      chunk
    end)
  end

  defp write_stream_to_file(stream, local_path, total_size, on_progress) do
    try do
      file = File.open!(local_path, [:write, :binary])
      bytes_written = write_chunks(stream, file, total_size, on_progress, 0)
      File.close(file)

      if bytes_written == total_size do
        :ok
      else
        {:error, :incomplete_download}
      end
    rescue
      e -> {:error, {:file_error, Exception.message(e)}}
    end
  end

  defp write_chunks(stream, file, total_size, on_progress, acc) do
    Enum.reduce(stream, acc, fn chunk, bytes_so_far ->
      IO.binwrite(file, chunk)
      new_bytes = bytes_so_far + byte_size(chunk)
      on_progress.(new_bytes, total_size)
      new_bytes
    end)
  end
end
