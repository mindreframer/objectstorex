# Streaming Guide

This guide covers efficient handling of large files using ObjectStoreX streaming capabilities.

## Table of Contents

- [Why Streaming?](#why-streaming)
- [Streaming Downloads](#streaming-downloads)
- [Streaming Uploads](#streaming-uploads)
- [Streaming Lists](#streaming-lists)
- [Range Reads](#range-reads)
- [Best Practices](#best-practices)
- [Performance Tuning](#performance-tuning)

## Why Streaming?

Streaming is essential for handling large files without loading them entirely into memory:

- **Memory efficient**: Process files larger than available RAM
- **Faster time-to-first-byte**: Start processing before full download completes
- **Better resource utilization**: Constant memory usage regardless of file size
- **Scalability**: Handle thousands of concurrent operations

## Streaming Downloads

Download large files in chunks without loading the entire file into memory.

### Basic Download Stream

```elixir
alias ObjectStoreX.Stream

# Create a download stream
stream = Stream.download(store, "large-file.bin")

# Write to disk
File.open!("local-file.bin", [:write], fn file ->
  stream
  |> Enum.each(&IO.binwrite(file, &1))
end)
```

### Process Chunks

```elixir
# Count total bytes
total_bytes =
  Stream.download(store, "large-file.bin")
  |> Stream.map(&byte_size/1)
  |> Enum.sum()

IO.puts "Total size: #{total_bytes} bytes"
```

### With Progress Tracking

```elixir
defmodule Downloader do
  def download_with_progress(store, remote_path, local_path) do
    {:ok, meta} = ObjectStoreX.head(store, remote_path)
    total_size = meta.size
    downloaded = 0

    File.open!(local_path, [:write], fn file ->
      ObjectStoreX.Stream.download(store, remote_path)
      |> Stream.each(fn chunk ->
        IO.binwrite(file, chunk)
        downloaded = downloaded + byte_size(chunk)
        progress = Float.round(downloaded / total_size * 100, 1)
        IO.write("\rProgress: #{progress}%")
      end)
      |> Stream.run()
    end)

    IO.puts("\n✓ Download complete")
  end
end
```

### Timeout Configuration

```elixir
# Set custom timeout for each chunk (default: 30 seconds)
stream = Stream.download(store, "large-file.bin", timeout: 60_000)
```

### Error Handling

```elixir
try do
  Stream.download(store, "large-file.bin")
  |> Stream.into(File.stream!("output.bin"))
  |> Stream.run()
rescue
  error ->
    IO.puts "Download failed: #{inspect(error)}"
end
```

## Streaming Uploads

Upload large files in chunks using multipart upload.

### Basic Upload Stream

```elixir
# Upload from file (10MB chunks)
File.stream!("large-file.bin", [], 10_485_760)
|> ObjectStoreX.Stream.upload(store, "remote-file.bin")
```

### From Generated Data

```elixir
# Upload randomly generated data
Stream.repeatedly(fn -> :crypto.strong_rand_bytes(1_048_576) end)
|> Stream.take(1000)  # 1GB total (1000 * 1MB)
|> ObjectStoreX.Stream.upload(store, "random-data.bin")
```

### From External Source

```elixir
# Upload from HTTP response
HTTPoison.get!("https://example.com/large-file.bin", stream_to: self())

stream = Stream.resource(
  fn -> :ok end,
  fn acc ->
    receive do
      %HTTPoison.AsyncChunk{chunk: data} -> {[data], acc}
      %HTTPoison.AsyncEnd{} -> {:halt, acc}
    after
      30_000 -> raise "Timeout"
    end
  end,
  fn _acc -> :ok end
)

ObjectStoreX.Stream.upload(stream, store, "downloaded-file.bin")
```

### With Progress Tracking

```elixir
defmodule Uploader do
  def upload_with_progress(local_path, store, remote_path, chunk_size \\ 10_485_760) do
    file_size = File.stat!(local_path).size
    uploaded = 0

    File.stream!(local_path, [], chunk_size)
    |> Stream.each(fn chunk ->
      uploaded = uploaded + byte_size(chunk)
      progress = Float.round(uploaded / file_size * 100, 1)
      IO.write("\rUploading: #{progress}%")
    end)
    |> ObjectStoreX.Stream.upload(store, remote_path)

    IO.puts("\n✓ Upload complete")
  end
end
```

### Error Handling

```elixir
case ObjectStoreX.Stream.upload(stream, store, "file.bin") do
  :ok ->
    IO.puts "✓ Upload successful"

  {:error, reason} ->
    IO.puts "✗ Upload failed: #{inspect(reason)}"
    # Multipart upload is automatically aborted on error
end
```

## Streaming Lists

List large numbers of objects efficiently with automatic pagination.

### Basic List Stream

```elixir
# List all objects with prefix
ObjectStoreX.Stream.list_stream(store, prefix: "data/2025/")
|> Stream.map(fn meta -> meta.location end)
|> Enum.to_list()
```

### Filter Results

```elixir
# Find large files
large_files =
  ObjectStoreX.Stream.list_stream(store, prefix: "uploads/")
  |> Stream.filter(fn meta -> meta.size > 100_000_000 end)  # > 100MB
  |> Stream.map(fn meta -> {meta.location, meta.size} end)
  |> Enum.to_list()
```

### Process in Batches

```elixir
# Delete in batches of 1000
ObjectStoreX.Stream.list_stream(store, prefix: "temp/")
|> Stream.map(fn meta -> meta.location end)
|> Stream.chunk_every(1000)
|> Stream.each(fn batch ->
  {:ok, deleted, _failed} = ObjectStoreX.delete_many(store, batch)
  IO.puts "Deleted batch: #{deleted} objects"
end)
|> Stream.run()
```

### Lazy Evaluation

```elixir
# Only fetch first 10 objects (stops pagination early)
first_10 =
  ObjectStoreX.Stream.list_stream(store)
  |> Stream.take(10)
  |> Enum.to_list()
```

### Aggregate Statistics

```elixir
# Calculate total size of all objects
total_size =
  ObjectStoreX.Stream.list_stream(store, prefix: "backups/")
  |> Stream.map(fn meta -> meta.size end)
  |> Enum.sum()

IO.puts "Total backup size: #{total_size} bytes"
```

## Range Reads

Read specific byte ranges without downloading entire files.

### Single Range

```elixir
# Read first 1000 bytes
{:ok, data, meta} = ObjectStoreX.get(store, "file.bin", range: {0, 999})
```

### Multiple Ranges

```elixir
# Read header and footer (e.g., Parquet file)
{:ok, [header, footer]} = ObjectStoreX.get_ranges(store, "data.parquet", [
  {0, 1000},           # Header
  {9_999_000, 10_000_000}  # Footer
])

# Parse metadata without downloading full file
parse_parquet_metadata(header, footer)
```

### Video File Preview

```elixir
# Extract video metadata from header
{:ok, [header, metadata_section]} = ObjectStoreX.get_ranges(store, "video.mp4", [
  {0, 100},     # File header
  {500, 2000}   # Metadata section
])

video_info = parse_video_header(header, metadata_section)
```

### Parallel Range Reads

```elixir
# Read multiple files in parallel
files = ["file1.bin", "file2.bin", "file3.bin"]

tasks = Enum.map(files, fn file ->
  Task.async(fn ->
    {:ok, data, _meta} = ObjectStoreX.get(store, file, range: {0, 1000})
    {file, data}
  end)
end)

results = Task.await_many(tasks)
```

## Best Practices

### 1. Choose Appropriate Chunk Size

```elixir
# For uploads, larger chunks = fewer requests
# Recommended: 10-50MB for cloud providers

# Small files (<10MB): Single put
:ok = ObjectStoreX.put(store, "small.txt", data)

# Large files (>10MB): Streaming
File.stream!("large.bin", [], 10_485_760)  # 10MB chunks
|> ObjectStoreX.Stream.upload(store, "large.bin")
```

### 2. Handle Backpressure

```elixir
# Use Stream.chunk_every to batch operations
ObjectStoreX.Stream.list_stream(store)
|> Stream.chunk_every(100)
|> Stream.each(&process_batch/1)
|> Stream.run()
```

### 3. Implement Retry Logic

```elixir
defmodule RetryUploader do
  def upload_with_retry(stream, store, path, retries \\ 3) do
    case ObjectStoreX.Stream.upload(stream, store, path) do
      :ok ->
        :ok

      {:error, reason} when retries > 0 ->
        if ObjectStoreX.Error.retryable?(reason) do
          :timer.sleep(1000)
          upload_with_retry(stream, store, path, retries - 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### 4. Use Concurrent Streams

```elixir
# Process multiple files concurrently
files = ["file1.bin", "file2.bin", "file3.bin"]

files
|> Task.async_stream(fn file ->
  ObjectStoreX.Stream.download(store, file)
  |> Stream.into(File.stream!("local-#{file}"))
  |> Stream.run()
end, max_concurrency: 10)
|> Stream.run()
```

### 5. Monitor Memory Usage

```elixir
# Memory-efficient processing of large lists
ObjectStoreX.Stream.list_stream(store)
|> Stream.map(&process_object/1)
|> Stream.run()

# Avoid loading entire list into memory
# ❌ Don't do this:
all_objects = ObjectStoreX.Stream.list_stream(store) |> Enum.to_list()
```

## Performance Tuning

### Upload Performance

```elixir
# Optimal chunk size depends on:
# - Network bandwidth
# - File size
# - Provider (S3 prefers 5MB-5GB chunks)

# For S3, use 10-50MB chunks
chunk_size = 10_485_760  # 10MB

File.stream!(path, [], chunk_size)
|> ObjectStoreX.Stream.upload(store, remote_path)
```

### Download Performance

```elixir
# Parallel downloads for multiple files
paths = ["file1.bin", "file2.bin", "file3.bin"]

paths
|> Task.async_stream(
  fn path ->
    ObjectStoreX.Stream.download(store, path)
    |> Stream.into(File.stream!("local-#{path}"))
    |> Stream.run()
  end,
  max_concurrency: 10,
  timeout: :infinity
)
|> Stream.run()
```

### List Performance

```elixir
# Use prefix to narrow results
ObjectStoreX.Stream.list_stream(store, prefix: "data/2025/01/")

# Process in batches to avoid memory issues
|> Stream.chunk_every(1000)
|> Stream.each(&process_batch/1)
|> Stream.run()
```

## Real-World Examples

### Backup System

```elixir
defmodule BackupSystem do
  def backup_directory(local_dir, store, prefix) do
    File.ls!(local_dir)
    |> Task.async_stream(
      fn file ->
        local_path = Path.join(local_dir, file)
        remote_path = Path.join(prefix, file)

        File.stream!(local_path, [], 10_485_760)
        |> ObjectStoreX.Stream.upload(store, remote_path)
      end,
      max_concurrency: 5
    )
    |> Stream.run()
  end
end
```

### Log Processor

```elixir
defmodule LogProcessor do
  def process_logs(store, date) do
    prefix = "logs/#{date}/"

    ObjectStoreX.Stream.list_stream(store, prefix: prefix)
    |> Stream.flat_map(fn meta ->
      ObjectStoreX.Stream.download(store, meta.location)
    end)
    |> Stream.flat_map(&String.split(&1, "\n"))
    |> Stream.filter(&contains_error?/1)
    |> Enum.to_list()
  end

  defp contains_error?(line), do: String.contains?(line, "ERROR")
end
```

### Data Migration

```elixir
defmodule DataMigration do
  def migrate(source_store, dest_store, prefix) do
    ObjectStoreX.Stream.list_stream(source_store, prefix: prefix)
    |> Task.async_stream(
      fn meta ->
        # Stream from source to destination
        ObjectStoreX.Stream.download(source_store, meta.location)
        |> ObjectStoreX.Stream.upload(dest_store, meta.location)
      end,
      max_concurrency: 10,
      timeout: :infinity
    )
    |> Stream.run()
  end
end
```

## Next Steps

- [Getting Started Guide](getting_started.md)
- [Configuration Guide](configuration.md)
- [Distributed Systems Guide](distributed_systems.md)
- [Error Handling Guide](error_handling.md)
