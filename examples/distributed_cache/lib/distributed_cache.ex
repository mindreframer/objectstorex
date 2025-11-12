defmodule DistributedCache do
  @moduledoc """
  Example: Distributed cache with ETag-based invalidation.

  This example demonstrates how to use ObjectStoreX to build a distributed cache
  that uses ETags for efficient cache validation and synchronization across nodes.

  ## Features

  - ETag-based cache validation (HTTP 304 Not Modified)
  - Automatic cache invalidation when objects change
  - Memory-efficient with ETS storage
  - TTL (Time-To-Live) support for cache entries
  - Statistics tracking (hits, misses, invalidations)

  ## Architecture

  The cache works by:
  1. Storing objects locally in ETS with their ETag
  2. On cache hits, sending a conditional GET with `if_none_match: etag`
  3. If the object hasn't changed, receiving `:not_modified` (cache hit)
  4. If the object has changed, receiving new data and updating cache

  This provides distributed cache consistency without polling.

  ## Usage

      # Start the cache with a store
      {:ok, store} = ObjectStoreX.new(:s3,
        bucket: "cache-bucket",
        region: "us-east-1"
      )

      {:ok, _pid} = DistributedCache.start_link(store, ttl: 300_000)  # 5 min TTL

      # Get with automatic caching
      {:ok, value} = DistributedCache.get("config/settings.json")

      # Put and update cache
      :ok = DistributedCache.put("config/settings.json", value)

      # Invalidate specific key
      :ok = DistributedCache.invalidate("config/settings.json")

      # Get cache statistics
      stats = DistributedCache.stats()
      IO.inspect(stats)
      # => %{hits: 42, misses: 10, invalidations: 3, entries: 15}

  ## Example: Multi-node cache coordination

      # On Node A
      {:ok, store_a} = ObjectStoreX.new(:s3, bucket: "shared-cache", region: "us-east-1")
      {:ok, _} = DistributedCache.start_link(store_a, name: :cache_a)

      # On Node B
      {:ok, store_b} = ObjectStoreX.new(:s3, bucket: "shared-cache", region: "us-east-1")
      {:ok, _} = DistributedCache.start_link(store_b, name: :cache_b)

      # Node A writes and caches
      DistributedCache.put(:cache_a, "data.json", ~s({"version": 1}))

      # Node B reads (gets from S3, caches)
      {:ok, data} = DistributedCache.get(:cache_b, "data.json")

      # Node A updates
      DistributedCache.put(:cache_a, "data.json", ~s({"version": 2}))

      # Node B reads again - ETag changed, cache invalidated automatically
      {:ok, new_data} = DistributedCache.get(:cache_b, "data.json")
  """

  use GenServer
  require Logger

  @type cache_entry :: {String.t(), String.t() | nil, binary(), integer()}
  @type stats :: %{
          hits: non_neg_integer(),
          misses: non_neg_integer(),
          invalidations: non_neg_integer(),
          entries: non_neg_integer()
        }

  # Client API

  @doc """
  Start the distributed cache with a given object store.

  ## Options

  - `:name` - Name to register the GenServer (default: `__MODULE__`)
  - `:ttl` - Time-to-live for cache entries in milliseconds (default: 300_000 = 5 minutes)
  - `:max_size` - Maximum number of entries (default: 10_000)
  """
  @spec start_link(ObjectStoreX.store(), keyword()) :: GenServer.on_start()
  def start_link(store, opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, {store, opts}, name: name)
  end

  @doc """
  Get a value from the cache, fetching from object store if needed.

  Uses ETag-based validation for efficiency.
  """
  @spec get(GenServer.server(), String.t()) :: {:ok, binary()} | {:error, atom()}
  def get(server \\ __MODULE__, key) do
    GenServer.call(server, {:get, key})
  end

  @doc """
  Put a value into object storage and update the cache.
  """
  @spec put(GenServer.server(), String.t(), binary()) :: :ok | {:error, atom()}
  def put(server \\ __MODULE__, key, value) do
    GenServer.call(server, {:put, key, value})
  end

  @doc """
  Invalidate a specific cache entry.
  """
  @spec invalidate(GenServer.server(), String.t()) :: :ok
  def invalidate(server \\ __MODULE__, key) do
    GenServer.cast(server, {:invalidate, key})
  end

  @doc """
  Clear all cache entries.
  """
  @spec clear(GenServer.server()) :: :ok
  def clear(server \\ __MODULE__) do
    GenServer.cast(server, :clear)
  end

  @doc """
  Get cache statistics.
  """
  @spec stats(GenServer.server()) :: stats()
  def stats(server \\ __MODULE__) do
    GenServer.call(server, :stats)
  end

  # Server callbacks

  @impl true
  def init({store, opts}) do
    ttl = Keyword.get(opts, :ttl, 300_000)
    max_size = Keyword.get(opts, :max_size, 10_000)

    cache_table = :ets.new(:cache, [:set, :private])
    stats_table = :ets.new(:stats, [:set, :private])

    # Initialize stats
    :ets.insert(stats_table, {:hits, 0})
    :ets.insert(stats_table, {:misses, 0})
    :ets.insert(stats_table, {:invalidations, 0})

    # Schedule TTL cleanup
    schedule_cleanup(ttl)

    {:ok,
     %{
       store: store,
       cache: cache_table,
       stats: stats_table,
       ttl: ttl,
       max_size: max_size
     }}
  end

  @impl true
  def handle_call({:get, key}, _from, state) do
    result =
      case :ets.lookup(state.cache, key) do
        [{^key, etag, value, timestamp}] when not is_nil(etag) ->
          if expired?(timestamp, state.ttl) do
            # Expired, fetch fresh
            handle_cache_miss(state, key)
          else
            # Try conditional GET
            case ObjectStoreX.get(state.store, key, if_none_match: etag) do
              {:error, :not_modified} ->
                # Cache hit! Update timestamp
                :ets.insert(state.cache, {key, etag, value, current_time()})
                increment_stat(state.stats, :hits)
                {:ok, value}

              {:ok, new_value, meta} ->
                # Cache miss - object was modified
                :ets.insert(state.cache, {key, meta.etag, new_value, current_time()})
                increment_stat(state.stats, :misses)
                increment_stat(state.stats, :invalidations)
                {:ok, new_value}

              {:error, reason} ->
                # Error fetching - return cached value if available
                Logger.warning("Error fetching #{key}: #{inspect(reason)}, using cached value")
                {:ok, value}
            end
          end

        [] ->
          # Not cached, fetch from store
          handle_cache_miss(state, key)
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call({:put, key, value}, _from, state) do
    result =
      case ObjectStoreX.put(state.store, key, value) do
        :ok ->
          # Fetch metadata to get ETag
          case ObjectStoreX.head(state.store, key) do
            {:ok, meta} ->
              :ets.insert(state.cache, {key, meta.etag, value, current_time()})
              :ok

            {:error, _reason} ->
              # Store without ETag
              :ets.insert(state.cache, {key, nil, value, current_time()})
              :ok
          end

        {:error, reason} ->
          {:error, reason}
      end

    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    hits = get_stat(state.stats, :hits)
    misses = get_stat(state.stats, :misses)
    invalidations = get_stat(state.stats, :invalidations)
    entries = :ets.info(state.cache, :size)

    stats = %{
      hits: hits,
      misses: misses,
      invalidations: invalidations,
      entries: entries
    }

    {:reply, stats, state}
  end

  @impl true
  def handle_cast({:invalidate, key}, state) do
    :ets.delete(state.cache, key)
    increment_stat(state.stats, :invalidations)
    {:noreply, state}
  end

  @impl true
  def handle_cast(:clear, state) do
    :ets.delete_all_objects(state.cache)
    {:noreply, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired(state)
    schedule_cleanup(state.ttl)
    {:noreply, state}
  end

  # Private helpers

  defp handle_cache_miss(state, key) do
    # Get value and metadata
    with {:ok, value} <- ObjectStoreX.get(state.store, key),
         {:ok, meta} <- ObjectStoreX.head(state.store, key) do
      # Check max size and evict if needed
      if :ets.info(state.cache, :size) >= state.max_size do
        evict_oldest(state.cache)
      end

      :ets.insert(state.cache, {key, meta.etag, value, current_time()})
      increment_stat(state.stats, :misses)
      {:ok, value}
    else
      {:error, reason} ->
        increment_stat(state.stats, :misses)
        {:error, reason}
    end
  end

  defp expired?(timestamp, ttl) do
    current_time() - timestamp > ttl
  end

  defp current_time, do: System.monotonic_time(:millisecond)

  defp cleanup_expired(state) do
    cutoff = current_time() - state.ttl

    expired =
      :ets.select(state.cache, [
        {{:"$1", :_, :_, :"$2"}, [{:<, :"$2", cutoff}], [:"$1"]}
      ])

    Enum.each(expired, fn key ->
      :ets.delete(state.cache, key)
      increment_stat(state.stats, :invalidations)
    end)

    if length(expired) > 0 do
      Logger.debug("Cleaned up #{length(expired)} expired cache entries")
    end
  end

  defp evict_oldest(cache_table) do
    # Find the oldest entry
    oldest =
      :ets.select(cache_table, [
        {{:"$1", :_, :_, :"$2"}, [], [{{:"$1", :"$2"}}]}
      ])
      |> Enum.min_by(fn {_key, timestamp} -> timestamp end, fn -> nil end)

    case oldest do
      {key, _timestamp} ->
        :ets.delete(cache_table, key)
        Logger.debug("Evicted oldest cache entry: #{key}")

      nil ->
        :ok
    end
  end

  defp schedule_cleanup(ttl) do
    # Cleanup every 1/4 of TTL
    cleanup_interval = div(ttl, 4)
    Process.send_after(self(), :cleanup, cleanup_interval)
  end

  defp increment_stat(stats_table, key) do
    :ets.update_counter(stats_table, key, {2, 1}, {key, 0})
  end

  defp get_stat(stats_table, key) do
    case :ets.lookup(stats_table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end
end
