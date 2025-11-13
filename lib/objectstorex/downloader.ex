defmodule ObjectStoreX.Downloader do
  @moduledoc """
  Download a file from object storage with progress tracking.
  it requests the file in chunks, and downloads them concurrently.
  """

  @doc """
  Download a file from object storage with progress tracking.
  """
  def download_with_progress(store, remote_path, local_path, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 5)
    # 5MB chunks - balance between smooth progress and fewer S3 requests
    chunk_size = Keyword.get(opts, :chunk_size, 5 * 1024 * 1024)
    # Number of concurrent downloads
    concurrency = Keyword.get(opts, :concurrency, 4)

    {:ok, meta} = ObjectStoreX.head(store, remote_path)
    total_size = meta.size

    IO.puts("Downloading #{remote_path} to #{local_path}")
    IO.puts("Total size: #{total_size} bytes (#{format_bytes(total_size)})\n")

    # Check if partial download exists
    start_offset =
      if File.exists?(local_path) do
        %{size: size} = File.stat!(local_path)
        size
      else
        0
      end

    bytes_remaining = total_size - start_offset

    cond do
      bytes_remaining == 0 ->
        IO.puts("✓ File already complete")
        {:ok, :already_complete}

      bytes_remaining < 0 ->
        # Local file is larger than remote file - wrong file or corruption
        IO.puts(
          "⚠ Local file (#{format_bytes(start_offset)}) is larger than remote (#{format_bytes(total_size)})"
        )

        IO.puts("Removing local file and restarting download...")
        File.rm!(local_path)

        download_in_chunks(
          store,
          remote_path,
          local_path,
          total_size,
          0,
          chunk_size,
          max_retries,
          concurrency
        )

      bytes_remaining < 1024 ->
        # Less than 1KB remaining - download the tail end with special handling
        IO.puts("Downloading final #{bytes_remaining} bytes...")
        download_tail(store, remote_path, local_path, start_offset, total_size, max_retries)

      start_offset > 0 ->
        IO.puts("Resuming from byte #{start_offset} (#{format_bytes(start_offset)})")

        download_in_chunks(
          store,
          remote_path,
          local_path,
          total_size,
          start_offset,
          chunk_size,
          max_retries,
          concurrency
        )

      true ->
        download_in_chunks(
          store,
          remote_path,
          local_path,
          total_size,
          start_offset,
          chunk_size,
          max_retries,
          concurrency
        )
    end
  end

  defp download_tail(store, remote_path, local_path, start_offset, total_size, max_retries) do
    bytes_needed = total_size - start_offset
    IO.puts("Need to download #{bytes_needed} bytes from position #{start_offset}")

    # Workaround for Wasabi S3 bug: range requests ending at the very last byte position
    # consistently return one less byte than requested.
    # Solution: Download a larger chunk that starts well before the missing data,
    # truncate the local file to that earlier position, and rewrite the entire tail.

    # Determine how far back to go (at least 1MB or the whole file if smaller)
    rewind_size = min(1024 * 1024, start_offset)
    rewind_to = start_offset - rewind_size

    IO.puts("Redownloading from position #{rewind_to} to guarantee complete file")

    # Download from rewind position to end
    # IMPORTANT: Use a range end that's beyond the file size to work around Wasabi S3 bug
    # where requesting exactly to the last byte drops that byte from the response
    case download_chunk_with_retry(
           store,
           remote_path,
           {rewind_to, total_size + 1000},
           max_retries,
           0
         ) do
      {:ok, data} ->
        downloaded_bytes = byte_size(data)
        expected_bytes = total_size - rewind_to

        IO.puts("Downloaded #{downloaded_bytes} bytes (expected #{expected_bytes})")

        # Truncate file to rewind_to position
        existing_data = File.read!(local_path)
        truncated = binary_part(existing_data, 0, rewind_to)
        File.write!(local_path, truncated)

        # Append all the downloaded data
        file = File.open!(local_path, [:append])

        try do
          IO.binwrite(file, data)
          IO.puts("Rewrote final #{byte_size(data)} bytes")
        after
          File.close(file)
        end

        :ok

      {:error, reason} ->
        {:error, "Failed to download tail: #{inspect(reason)}"}
    end
  end

  defp download_in_chunks(
         store,
         remote_path,
         local_path,
         total_size,
         start_offset,
         chunk_size,
         max_retries,
         concurrency
       ) do
    # Create the file if it doesn't exist
    unless File.exists?(local_path) do
      File.write!(local_path, "")
    end

    # Calculate all chunk ranges
    chunks = calculate_chunk_ranges(start_offset, total_size, chunk_size)

    # Track progress across all tasks
    progress_agent = start_progress_tracker(total_size, start_offset)

    # Download chunks concurrently
    chunks
    |> Task.async_stream(
      fn {chunk_start, chunk_end} ->
        case download_chunk_with_retry(
               store,
               remote_path,
               {chunk_start, chunk_end},
               max_retries,
               0
             ) do
          {:ok, data} ->
            # Write data at the correct position
            file = File.open!(local_path, [:read, :write])

            try do
              :file.pwrite(file, chunk_start, data)
            after
              File.close(file)
            end

            # Update progress
            update_progress(progress_agent, byte_size(data), total_size)
            {:ok, byte_size(data)}

          {:error, reason} ->
            {:error, {chunk_start, chunk_end, reason}}
        end
      end,
      max_concurrency: concurrency,
      timeout: 120_000
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, {:ok, _size}}, :ok -> {:cont, :ok}
      {:ok, {:error, reason}}, _acc -> {:halt, {:error, reason}}
      {:exit, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      :ok ->
        stop_progress_tracker(progress_agent)
        IO.puts("\n✓ Download complete")
        :ok

      {:error, {chunk_start, chunk_end, reason}} ->
        stop_progress_tracker(progress_agent)
        {:error, "Failed to download chunk #{chunk_start}-#{chunk_end}: #{inspect(reason)}"}

      {:error, reason} ->
        stop_progress_tracker(progress_agent)
        {:error, reason}
    end
  end

  defp calculate_chunk_ranges(start_offset, total_size, chunk_size) do
    start_offset
    |> Stream.iterate(&(&1 + chunk_size))
    |> Stream.take_while(&(&1 < total_size))
    |> Enum.map(fn offset ->
      natural_end = offset + chunk_size - 1

      chunk_end =
        if natural_end >= total_size - 1 do
          # This chunk includes the last byte - request beyond EOF (Wasabi workaround)
          total_size + 1000
        else
          natural_end
        end

      {offset, chunk_end}
    end)
  end

  defp start_progress_tracker(_total_size, start_offset) do
    {:ok, agent} = Agent.start_link(fn -> start_offset end)
    agent
  end

  defp update_progress(agent, bytes_downloaded, total_size) do
    Agent.update(agent, fn current ->
      new_total = current + bytes_downloaded
      print_progress_bar(new_total, total_size)
      new_total
    end)
  end

  defp stop_progress_tracker(agent) do
    Agent.stop(agent)
  end

  defp download_chunk_with_retry(store, remote_path, {start_pos, end_pos}, max_retries, attempt) do
    case ObjectStoreX.get(store, remote_path, range: {start_pos, end_pos}) do
      {:ok, data, _meta} ->
        {:ok, data}

      {:error, reason} ->
        if attempt < max_retries do
          delay = (:math.pow(2, attempt) * 1000) |> round()
          Process.sleep(delay)

          download_chunk_with_retry(
            store,
            remote_path,
            {start_pos, end_pos},
            max_retries,
            attempt +
              1
          )
        else
          {:error, reason}
        end
    end
  end

  defp print_progress_bar(downloaded, total) do
    percentage = downloaded / total * 100
    bar_width = 40
    filled = round(bar_width * downloaded / total)
    empty = bar_width - filled

    bar = String.duplicate("█", filled) <> String.duplicate("░", empty)

    IO.write(
      "\r[#{bar}] #{Float.round(percentage, 1)}% (#{format_bytes(downloaded)}/#{format_bytes(total)})"
    )
  end

  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"

  defp format_bytes(bytes) when bytes < 1024 * 1024 * 1024,
    do:
      "#{Float.round(bytes / (1024 * 1024),
      1)} MB"

  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024 * 1024), 2)} GB"
end
