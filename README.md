# ObjectStoreX

[![Hex.pm](https://img.shields.io/hexpm/v/objectstorex.svg)](https://hex.pm/packages/objectstorex)
[![Documentation](https://img.shields.io/badge/docs-hexdocs-blue.svg)](https://hexdocs.pm/objectstorex)
[![CI](https://img.shields.io/github/workflow/status/yourorg/objectstorex/CI)](https://github.com/yourorg/objectstorex/actions)
[![Coverage](https://img.shields.io/codecov/c/github/yourorg/objectstorex)](https://codecov.io/gh/yourorg/objectstorex)
[![License](https://img.shields.io/hexpm/l/objectstorex.svg)](https://github.com/yourorg/objectstorex/blob/main/LICENSE)

**Unified object storage for Elixir** with production-ready features like Compare-And-Swap (CAS), conditional operations, streaming, and comprehensive error handling.

ObjectStoreX provides a **consistent API** across multiple cloud storage providers (AWS S3, Azure Blob Storage, Google Cloud Storage) and local storage, powered by the battle-tested Rust [`object_store`](https://github.com/apache/arrow-rs/tree/master/object_store) library via Rustler NIFs for near-native performance.

## Features

- **Multi-Provider Support**: AWS S3, Azure Blob Storage, GCS, local filesystem, in-memory storage
- **Advanced Operations**:
  - Compare-And-Swap (CAS) with ETags
  - Conditional GET/PUT operations
  - Create-only writes for distributed locks
  - Rich metadata and attributes
- **Performance**: High-performance Rust NIFs with async I/O
- **Streaming**: Support for large files with streaming uploads/downloads
- **Bulk Operations**: Efficient batch operations for multiple objects
- **Use Case Examples**: Distributed locks, optimistic counters, HTTP-style caching

## Installation

Add `objectstorex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:objectstorex, "~> 0.1.0"}
  ]
end
```

## Quick Start

```elixir
# Create an in-memory store for testing
{:ok, store} = ObjectStoreX.new(:memory)

# Store some data
:ok = ObjectStoreX.put(store, "test.txt", "Hello, World!")

# Retrieve it
{:ok, data} = ObjectStoreX.get(store, "test.txt")
# => "Hello, World!"

# Get metadata
{:ok, meta} = ObjectStoreX.head(store, "test.txt")
# => %{location: "test.txt", size: 13, etag: "...", ...}

# Delete it
:ok = ObjectStoreX.delete(store, "test.txt")
```

## Provider Configuration

### AWS S3

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1",
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
)
```

### Azure Blob Storage

```elixir
{:ok, store} = ObjectStoreX.new(:azure,
  account: "myaccount",
  container: "mycontainer",
  access_key: System.get_env("AZURE_STORAGE_KEY")
)
```

### Google Cloud Storage

```elixir
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket",
  service_account_key: File.read!("credentials.json")
)
```

### Local Filesystem

```elixir
{:ok, store} = ObjectStoreX.new(:local, path: "/tmp/storage")
```

## Advanced Features

### Compare-And-Swap (CAS) Operations

Use CAS for optimistic concurrency control:

```elixir
# Read current value with metadata
{:ok, data} = ObjectStoreX.get(store, "counter.json")
{:ok, meta} = ObjectStoreX.head(store, "counter.json")

# Update only if version matches (CAS)
new_data = update_value(data)

case ObjectStoreX.put(store, "counter.json", new_data,
       mode: {:update, %{etag: meta.etag, version: meta.version}}) do
  {:ok, _} -> :success
  {:error, :precondition_failed} -> :retry  # Someone else modified it
end
```

### Create-Only Writes (Distributed Locks)

Implement distributed locks with atomic create operations:

```elixir
lock_data = Jason.encode!(%{holder: node(), timestamp: System.system_time()})

case ObjectStoreX.put(store, "locks/resource-123", lock_data, mode: :create) do
  {:ok, _} -> :lock_acquired
  {:error, :already_exists} -> :locked_by_other
end
```

### Conditional GET (HTTP-Style Caching)

Minimize data transfer with conditional requests:

```elixir
# First fetch
{:ok, data, meta} = ObjectStoreX.get(store, "data.json")
cached_etag = meta.etag

# Later fetch - only download if changed
case ObjectStoreX.get(store, "data.json", if_none_match: cached_etag) do
  {:error, :not_modified} -> use_cached_data()
  {:ok, new_data} -> update_cache(new_data)
end
```

### Rich Metadata and Attributes

Upload objects with content metadata:

```elixir
ObjectStoreX.put(store, "report.pdf", pdf_data,
  content_type: "application/pdf",
  content_disposition: "attachment; filename=report.pdf",
  cache_control: "max-age=3600"
)
```

## Use Case Examples

ObjectStoreX includes complete, production-ready examples for common distributed systems patterns:

### 1. Distributed Lock (`examples/distributed_lock.ex`)

Implement distributed locking for coordinating tasks across multiple nodes:

```elixir
alias ObjectStoreX.Examples.DistributedLock

# Acquire lock
case DistributedLock.acquire(store, "resource-123") do
  {:ok, lock_info} ->
    try do
      # Do exclusive work
      process_resource()
    after
      DistributedLock.release(store, "resource-123")
    end

  {:error, :locked} ->
    IO.puts("Resource is locked by another process")
end

# Acquire with retry and exponential backoff
{:ok, _} = DistributedLock.acquire_with_retry(store, "resource-123",
  max_retries: 5,
  initial_delay_ms: 100
)
```

Features:
- Atomic lock acquisition with `:create` mode
- Lock staleness detection and automatic cleanup
- Retry with exponential backoff
- Custom metadata support

### 2. Optimistic Counter (`examples/optimistic_counter.ex`)

Implement distributed counters with CAS-based optimistic locking:

```elixir
alias ObjectStoreX.Examples.OptimisticCounter

# Initialize counter
OptimisticCounter.initialize(store, "page-views", 0)

# Increment (automatically retries on conflict)
{:ok, new_value} = OptimisticCounter.increment(store, "page-views")

# Multiple processes can safely increment concurrently
tasks = for _ <- 1..10 do
  Task.async(fn -> OptimisticCounter.increment(store, "page-views") end)
end
Task.await_many(tasks)

# Decrement with minimum value constraint
{:ok, stock} = OptimisticCounter.decrement(store, "inventory-item-123",
  min_value: 0
)

# Custom update function
{:ok, new_val} = OptimisticCounter.update(store, "counter", fn v -> v * 2 end)
```

Features:
- CAS-based atomic updates with automatic retry
- Increment/decrement operations
- Custom update functions
- Minimum value constraints
- Exponential backoff on conflict

### 3. HTTP Cache (`examples/http_cache.ex`)

Implement efficient caching with ETag-based validation:

```elixir
alias ObjectStoreX.Examples.HTTPCache

# Start cache
{:ok, cache} = HTTPCache.start_cache("my_cache")

# First fetch - cache miss
{:ok, data, :miss} = HTTPCache.get_cached(store, "data.json", cache)

# Second fetch - cache hit (no data transfer if unchanged)
{:ok, data, :hit} = HTTPCache.get_cached(store, "data.json", cache)

# Get statistics
stats = HTTPCache.stats(cache)
# => %{hits: 1, misses: 1, entries: 1, hit_rate: 50.0}

# Manual invalidation
HTTPCache.invalidate(cache, "data.json")

# Clear all entries
HTTPCache.clear(cache)
```

Features:
- ETag-based conditional GET with `if_none_match`
- ETS-backed in-memory cache
- Automatic cache invalidation on changes
- Hit/miss statistics and hit rate tracking
- Support for `if_modified_since` timestamps

## Streaming and Bulk Operations

### Streaming Uploads/Downloads

```elixir
# Stream upload from file
stream = File.stream!("large-file.bin", [], 64 * 1024)
:ok = ObjectStoreX.put_stream(store, "large-file.bin", stream)

# Stream download to file
stream = ObjectStoreX.get_stream(store, "large-file.bin")
Stream.into(stream, File.stream!("downloaded.bin"))
|> Stream.run()
```

### Bulk Operations

```elixir
# Delete multiple objects
paths = ["file1.txt", "file2.txt", "file3.txt"]
:ok = ObjectStoreX.delete_many(store, paths)

# Get multiple byte ranges
ranges = [{0, 1000}, {5000, 6000}]
{:ok, chunks} = ObjectStoreX.get_ranges(store, "file.bin", ranges)
```

## Conditional Copy Operations

```elixir
# Atomic copy (only if destination doesn't exist)
case ObjectStoreX.copy_if_not_exists(store, "source.txt", "backup.txt") do
  :ok -> :copied
  {:error, :already_exists} -> :destination_exists
  {:error, :not_supported} -> :provider_not_supported
end

# Atomic rename
case ObjectStoreX.rename_if_not_exists(store, "old.txt", "new.txt") do
  :ok -> :renamed
  {:error, :already_exists} -> :destination_exists
end
```

## Testing

Run the test suite:

```bash
mix test
```

Run integration tests:

```bash
mix test test/integration/
```

Run quality checks:

```bash
./bin/qa_check.sh
```

## Provider Support Matrix

| Feature | S3 | Azure | GCS | Local | Memory |
|---------|-----|-------|-----|-------|--------|
| PutMode::Create | ✅ | ✅ | ✅ | ✅ | ✅ |
| PutMode::Update (ETag) | ✅ | ✅ | ✅ | ✅ | ✅ |
| PutMode::Update (Version) | ✅ | ❌ | ✅ | ❌ | ❌ |
| if_match | ✅ | ✅ | ✅ | ✅ | ✅ |
| if_none_match | ✅ | ✅ | ✅ | ✅ | ✅ |
| if_modified_since | ✅ | ✅ | ✅ | ✅ | ✅ |
| Attributes | ✅ | ✅ | ✅ | ⚠️ | ⚠️ |
| Tags | ✅ | ❌ | ✅ | ❌ | ❌ |
| copy_if_not_exists | ❌ | ✅ | ✅ | ✅ | ✅ |

Legend:
- ✅ Fully supported
- ⚠️ Partially supported (limited attributes)
- ❌ Not supported

## Documentation

### Guides

- **[Getting Started](guides/getting_started.md)** - Installation and basic usage
- **[Configuration](guides/configuration.md)** - Provider-specific configuration options
- **[Streaming](guides/streaming.md)** - Efficient handling of large files
- **[Distributed Systems](guides/distributed_systems.md)** - Locks, CAS, and caching patterns
- **[Error Handling](guides/error_handling.md)** - Comprehensive error handling and retry strategies

### API Reference

Full API documentation is available at [HexDocs](https://hexdocs.pm/objectstorex).

## Performance

ObjectStoreX uses high-performance Rust NIFs with async I/O for optimal throughput:

| Operation | Expected Performance |
|-----------|---------------------|
| Basic put/get | ~50ms (network dependent) |
| CAS put (success) | Same as regular put |
| CAS put (conflict) | <30ms (fast fail) |
| Conditional get (not modified) | <20ms (no transfer) |
| Streaming (large files) | ~100MB/s+ |
| Bulk operations | Parallel execution |

## License

Copyright 2024. Licensed under the MIT License.

## Credits

Built with:
- [object_store](https://github.com/apache/arrow-rs/tree/master/object_store) - High-performance Rust object storage abstraction
- [Rustler](https://github.com/rusterlium/rustler) - Safe Rust bridge for Elixir NIFs

