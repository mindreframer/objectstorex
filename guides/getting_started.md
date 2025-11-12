# Getting Started with ObjectStoreX

This guide will walk you through setting up and using ObjectStoreX in your Elixir application.

## Installation

Add `objectstorex` to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:objectstorex, "~> 0.1.0"}
  ]
end
```

Then install the dependencies:

```bash
mix deps.get
```

## Your First Store

Let's start with an in-memory store, which is perfect for testing and development:

```elixir
# Create an in-memory store
{:ok, store} = ObjectStoreX.new(:memory)

# Upload some data
:ok = ObjectStoreX.put(store, "hello.txt", "Hello, World!")

# Download it back
{:ok, data} = ObjectStoreX.get(store, "hello.txt")
IO.puts data
# => "Hello, World!"

# Get metadata
{:ok, meta} = ObjectStoreX.head(store, "hello.txt")
IO.inspect(meta)
# => %{location: "hello.txt", size: 13, last_modified: "...", etag: "..."}

# Delete the object
:ok = ObjectStoreX.delete(store, "hello.txt")
```

## Working with Local Filesystem

For local development, you can use the local filesystem provider:

```elixir
# Create a local store
{:ok, store} = ObjectStoreX.new(:local, path: "/tmp/my-storage")

# Now you can use it just like the memory store
:ok = ObjectStoreX.put(store, "data/file.txt", "Some data")
{:ok, data} = ObjectStoreX.get(store, "data/file.txt")
```

The local provider creates subdirectories automatically based on your object paths.

## Connecting to AWS S3

To use Amazon S3 (or S3-compatible services like MinIO or Cloudflare R2):

```elixir
# Using environment variables for credentials
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1",
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
)

# Or use default credential chain (environment, IAM role, etc.)
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1"
)
```

## Connecting to Azure Blob Storage

For Azure Blob Storage:

```elixir
{:ok, store} = ObjectStoreX.new(:azure,
  account: "myaccount",
  container: "mycontainer",
  access_key: System.get_env("AZURE_STORAGE_KEY")
)

# Or use connection string
{:ok, store} = ObjectStoreX.new(:azure,
  account: "myaccount",
  container: "mycontainer",
  connection_string: System.get_env("AZURE_STORAGE_CONNECTION_STRING")
)
```

## Connecting to Google Cloud Storage

For Google Cloud Storage:

```elixir
# Using service account key file
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket",
  service_account_key: File.read!("credentials.json")
)

# Or use Application Default Credentials
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket"
)
```

## Basic Operations

### Uploading Objects

```elixir
# Simple upload
:ok = ObjectStoreX.put(store, "data.txt", "Hello, World!")

# Upload with content type
:ok = ObjectStoreX.put(store, "data.json", json_data,
  content_type: "application/json"
)

# Upload with cache control
:ok = ObjectStoreX.put(store, "static/logo.png", image_data,
  content_type: "image/png",
  cache_control: "public, max-age=3600"
)
```

### Downloading Objects

```elixir
# Simple download
{:ok, data} = ObjectStoreX.get(store, "data.txt")

# Download with metadata
{:ok, data, meta} = ObjectStoreX.get(store, "data.txt", head: false)
IO.inspect(meta)
# => %{location: "data.txt", size: 13, etag: "...", ...}
```

### Listing Objects

```elixir
# List with streaming (recommended for large result sets)
ObjectStoreX.Stream.list_stream(store, prefix: "data/")
|> Stream.map(fn meta -> meta.location end)
|> Enum.take(10)
# => ["data/file1.txt", "data/file2.txt", ...]

# List with delimiter (simulates directory structure)
{:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store, prefix: "data/")
# objects => [%{location: "data/file.txt", ...}]
# prefixes => ["data/2024/", "data/2025/"]
```

### Deleting Objects

```elixir
# Delete single object
:ok = ObjectStoreX.delete(store, "data.txt")

# Delete multiple objects
{:ok, deleted, failed} = ObjectStoreX.delete_many(store, [
  "file1.txt",
  "file2.txt",
  "file3.txt"
])
IO.puts "Deleted: #{deleted}, Failed: #{length(failed)}"
```

### Copying and Moving Objects

```elixir
# Copy object (server-side, no download/upload)
:ok = ObjectStoreX.copy(store, "source.txt", "destination.txt")

# Rename/move object
:ok = ObjectStoreX.rename(store, "old-name.txt", "new-name.txt")
```

## Error Handling

All ObjectStoreX operations return tagged tuples for easy pattern matching:

```elixir
case ObjectStoreX.get(store, "file.txt") do
  {:ok, data} ->
    process_data(data)

  {:error, :not_found} ->
    Logger.warning("File not found")
    :file_missing

  {:error, :permission_denied} ->
    Logger.error("Permission denied")
    :unauthorized

  {:error, reason} ->
    Logger.error("Unexpected error: #{inspect(reason)}")
    :error
end
```

Common error atoms:
- `:not_found` - Object doesn't exist
- `:already_exists` - Object already exists (create-only mode)
- `:permission_denied` - Insufficient permissions
- `:timeout` - Operation timed out
- `:network_error` - Network/connection error
- `:precondition_failed` - Conditional operation failed
- `:not_modified` - Object not modified (conditional GET)

See the [Error Handling Guide](error_handling.md) for more details.

## Next Steps

Now that you understand the basics, explore these advanced topics:

- **[Configuration Guide](configuration.md)** - Detailed provider configuration options
- **[Streaming Guide](streaming.md)** - Handle large files efficiently
- **[Distributed Systems Guide](distributed_systems.md)** - Locks, CAS, and caching patterns
- **[Error Handling Guide](error_handling.md)** - Retry strategies and error patterns

## Quick Reference

```elixir
# Create store
{:ok, store} = ObjectStoreX.new(:memory)
{:ok, store} = ObjectStoreX.new(:local, path: "/tmp/storage")
{:ok, store} = ObjectStoreX.new(:s3, bucket: "my-bucket", region: "us-east-1")

# Basic operations
:ok = ObjectStoreX.put(store, "path.txt", "data")
{:ok, data} = ObjectStoreX.get(store, "path.txt")
{:ok, meta} = ObjectStoreX.head(store, "path.txt")
:ok = ObjectStoreX.delete(store, "path.txt")

# Copy/rename
:ok = ObjectStoreX.copy(store, "src.txt", "dst.txt")
:ok = ObjectStoreX.rename(store, "old.txt", "new.txt")

# Bulk operations
{:ok, deleted, failed} = ObjectStoreX.delete_many(store, ["f1.txt", "f2.txt"])

# Streaming
stream = ObjectStoreX.Stream.list_stream(store, prefix: "data/")
File.stream!("large.bin") |> ObjectStoreX.Stream.upload(store, "remote.bin")
ObjectStoreX.Stream.download(store, "large.bin") |> Stream.into(File.stream!("local.bin"))
```
