# File Uploader Example

This example demonstrates how to use ObjectStoreX to upload and download large files with progress tracking.

## Features

- **Chunked uploads**: Files are uploaded in configurable chunks for efficient memory usage
- **Progress tracking**: Real-time progress callbacks during upload/download
- **Streaming**: No need to load entire files into memory
- **Multi-provider**: Works with S3, Azure, GCS, and local storage

## Installation

```bash
cd examples/file_uploader
mix deps.get
```

## Usage

### Basic Upload

```elixir
# Start with local storage for testing
{:ok, store} = ObjectStoreX.new(:local, root: "/tmp/uploads")

# Upload a file
FileUploader.upload_file(store, "my-large-file.bin", "uploads/file.bin")
```

### Upload with Progress Tracking

```elixir
{:ok, store} = ObjectStoreX.new(:local, root: "/tmp/uploads")

FileUploader.upload_file(store, "my-large-file.bin", "uploads/file.bin",
  on_progress: fn bytes, total ->
    percentage = trunc(bytes / total * 100)
    IO.puts("Uploaded: #{bytes}/#{total} (#{percentage}%)")
  end
)
```

### Download with Progress

```elixir
{:ok, store} = ObjectStoreX.new(:local, root: "/tmp/uploads")

FileUploader.download_file(store, "uploads/file.bin", "downloaded-file.bin",
  on_progress: fn bytes, total ->
    percentage = trunc(bytes / total * 100)
    IO.puts("Downloaded: #{bytes}/#{total} (#{percentage}%)")
  end
)
```

### List Files with Sizes

```elixir
{:ok, store} = ObjectStoreX.new(:local, root: "/tmp/uploads")

FileUploader.list_files(store, prefix: "uploads/")
|> Stream.each(fn meta ->
  size = FileUploader.format_size(meta.size)
  IO.puts("#{meta.location} - #{size}")
end)
|> Stream.run()
```

## Using with S3

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1"
)

FileUploader.upload_file(store, "large-file.bin", "uploads/file.bin",
  chunk_size: 10_485_760,  # 10MB chunks
  on_progress: fn bytes, total ->
    IO.write("\rProgress: #{trunc(bytes/total*100)}%")
  end
)
```

## Running Tests

```bash
mix test
```

## API Reference

### `upload_file/4`

Upload a file to object storage with progress tracking.

**Options:**
- `:chunk_size` - Size of each chunk in bytes (default: 10MB)
- `:on_progress` - Callback function `(bytes_uploaded, total_size) -> any()`

### `download_file/4`

Download a file from object storage with progress tracking.

**Options:**
- `:on_progress` - Callback function `(bytes_downloaded, total_size) -> any()`

### `list_files/2`

List all files in a directory with size information.

**Options:**
- `:prefix` - Directory prefix to list

### `format_size/1`

Format file size in human-readable format (KB, MB, GB).

## License

Same as ObjectStoreX (Apache 2.0)
