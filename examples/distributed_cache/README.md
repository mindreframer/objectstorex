# Distributed Cache Example

This example demonstrates how to use ObjectStoreX to build a distributed cache with ETag-based invalidation.

## Features

- **ETag-based validation**: Uses HTTP ETags for efficient cache invalidation
- **Automatic cache updates**: Detects when objects change in storage
- **TTL support**: Configurable time-to-live for cache entries
- **Statistics tracking**: Monitor cache hits, misses, and invalidations
- **Memory efficient**: Uses ETS for in-memory storage
- **LRU eviction**: Automatically evicts oldest entries when cache is full

## How It Works

The cache uses ETags to efficiently validate cached data:

1. **First access**: Fetches object from storage, stores value + ETag in cache
2. **Cache hit**: Sends conditional GET with `if_none_match: etag`
   - If object unchanged: Server returns `:not_modified`, cache hit!
   - If object changed: Server returns new data + new ETag, cache updated
3. **TTL expiration**: Old entries are automatically cleaned up

This provides strong consistency without polling or manual invalidation.

## Installation

```bash
cd examples/distributed_cache
mix deps.get
```

## Usage

### Basic Usage

```elixir
# Create a store
{:ok, store} = ObjectStoreX.new(:local, root: "/tmp/cache")

# Start the cache
{:ok, _pid} = DistributedCache.start_link(store, ttl: 300_000)

# Put some data
:ok = DistributedCache.put("config.json", ~s({"version": 1}))

# Get data (cache miss - fetches from store)
{:ok, data} = DistributedCache.get("config.json")

# Get again (cache hit - validates with ETag)
{:ok, data} = DistributedCache.get("config.json")

# Check statistics
stats = DistributedCache.stats()
IO.inspect(stats)
# => %{hits: 1, misses: 1, invalidations: 0, entries: 1}
```

### Multi-Node Scenario

```elixir
# Node A
{:ok, store_a} = ObjectStoreX.new(:s3,
  bucket: "shared-cache",
  region: "us-east-1"
)
{:ok, _} = DistributedCache.start_link(store_a, name: :cache_a)

# Node B
{:ok, store_b} = ObjectStoreX.new(:s3,
  bucket: "shared-cache",
  region: "us-east-1"
)
{:ok, _} = DistributedCache.start_link(store_b, name: :cache_b)

# Node A writes
DistributedCache.put(:cache_a, "data.json", ~s({"version": 1}))

# Node B reads (miss, fetches from S3)
{:ok, v1} = DistributedCache.get(:cache_b, "data.json")

# Node A updates
DistributedCache.put(:cache_a, "data.json", ~s({"version": 2}))

# Node B reads again (ETag changed, automatic invalidation)
{:ok, v2} = DistributedCache.get(:cache_b, "data.json")
```

### Configuration Options

```elixir
DistributedCache.start_link(store,
  name: :my_cache,        # GenServer name
  ttl: 600_000,          # 10 minutes
  max_size: 5000         # Max 5000 cached entries
)
```

### Cache Management

```elixir
# Invalidate specific key
DistributedCache.invalidate("config.json")

# Clear entire cache
DistributedCache.clear()

# Get statistics
stats = DistributedCache.stats()
# => %{
#   hits: 150,
#   misses: 25,
#   invalidations: 5,
#   entries: 200
# }
```

## Use Cases

### Configuration Management

Cache application configuration files with automatic reloading:

```elixir
defmodule Config do
  def get(key) do
    case DistributedCache.get("config/#{key}.json") do
      {:ok, json} -> Jason.decode(json)
      error -> error
    end
  end

  def update(key, value) do
    json = Jason.encode!(value)
    DistributedCache.put("config/#{key}.json", json)
  end
end
```

### Content Caching

Cache frequently accessed content with ETag validation:

```elixir
defmodule ContentCache do
  def get_page(path) do
    case DistributedCache.get("pages/#{path}.html") do
      {:ok, html} -> {:ok, html}
      {:error, :not_found} -> {:error, :page_not_found}
    end
  end

  def publish_page(path, html) do
    DistributedCache.put("pages/#{path}.html", html)
  end
end
```

## Performance Benefits

1. **Reduced bandwidth**: ETag validation uses HTTP 304 Not Modified
2. **Lower latency**: Cached values served from memory
3. **Cost savings**: Fewer GET requests to cloud storage
4. **Scalability**: Distributed nodes share storage but have local caches

## Running Tests

```bash
mix test
```

## License

Same as ObjectStoreX (Apache 2.0)
