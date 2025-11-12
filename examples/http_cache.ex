defmodule ObjectStoreX.Examples.HTTPCache do
  @moduledoc """
  HTTP-style caching implementation using ETag-based conditional GET operations.

  This module demonstrates how to implement efficient caching using ObjectStoreX's
  conditional GET operations with ETags. It mimics HTTP caching semantics
  (If-None-Match, If-Modified-Since) to minimize data transfer when content hasn't changed.

  ## Features

  - ETag-based cache validation
  - Conditional GET with `if_none_match`
  - ETS-based in-memory cache
  - Automatic cache invalidation
  - Cache statistics tracking

  ## Example

      # Start cache
      {:ok, cache} = HTTPCache.start_cache("my_cache")

      {:ok, store} = ObjectStoreX.new(:memory)
      ObjectStoreX.put(store, "data.json", ~s({"value": 42}))

      # First fetch - cache miss
      {:ok, data, :miss} = HTTPCache.get_cached(store, "data.json", cache)
      # => {"{\"value\": 42}", :miss}

      # Second fetch - cache hit (no data transfer)
      {:ok, data, :hit} = HTTPCache.get_cached(store, "data.json", cache)
      # => {"{\"value\": 42}", :hit}

      # Get cache statistics
      stats = HTTPCache.stats(cache)
      # => %{hits: 1, misses: 1, entries: 1}

  ## Use Cases

  - CDN-style content caching
  - Reducing bandwidth usage
  - Improving read performance
  - Caching static assets
  - API response caching
  """

  require Logger

  @type cache_ref :: :ets.table()
  @type cache_entry :: {path :: String.t(), etag :: String.t(), data :: binary()}
  @type cache_result :: {:ok, binary(), :hit | :miss} | {:error, atom()}

  @doc """
  Starts a new ETS-based cache.

  ## Parameters

    - `name` - Cache name (atom or string)
    - `opts` - Optional keyword list:
      - `:type` - ETS table type (default: :set)
      - `:protection` - ETS protection level (default: :public)

  ## Returns

    - `{:ok, cache_ref}` - Cache started successfully
    - `{:error, reason}` - Error starting cache

  ## Examples

      iex> HTTPCache.start_cache("my_cache")
      {:ok, #Reference<...>}
  """
  @spec start_cache(atom() | String.t(), keyword()) :: {:ok, cache_ref()} | {:error, atom()}
  def start_cache(name, opts \\ []) do
    table_name = cache_table_name(name)
    stats_name = stats_table_name(name)
    table_type = Keyword.get(opts, :type, :set)
    protection = Keyword.get(opts, :protection, :public)

    try do
      cache_table = :ets.new(table_name, [table_type, protection, :named_table])
      stats_table = :ets.new(stats_name, [:set, protection, :named_table])

      # Initialize stats
      :ets.insert(stats_table, {:hits, 0})
      :ets.insert(stats_table, {:misses, 0})
      :ets.insert(stats_table, {:invalidations, 0})

      {:ok, cache_table}
    rescue
      e -> {:error, e}
    end
  end

  @doc """
  Retrieves data with caching using ETag validation.

  Uses conditional GET with `if_none_match` to validate cache entries.
  If the ETag matches (content unchanged), returns cached data without transfer.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `path` - Object path
    - `cache` - Cache reference from `start_cache/1`

  ## Returns

    - `{:ok, data, :hit}` - Cache hit, data unchanged
    - `{:ok, data, :miss}` - Cache miss or data changed
    - `{:error, reason}` - Error fetching data

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> ObjectStoreX.put(store, "file.txt", "content")
      iex> HTTPCache.get_cached(store, "file.txt", cache)
      {:ok, "content", :miss}
      iex> HTTPCache.get_cached(store, "file.txt", cache)
      {:ok, "content", :hit}
  """
  @spec get_cached(ObjectStoreX.store(), String.t(), cache_ref()) :: cache_result()
  def get_cached(store, path, cache) do
    cache_table = cache
    stats_table = derive_stats_table(cache)

    case lookup_cache(cache_table, path) do
      {:ok, cached_etag, cached_data} ->
        # Try conditional GET with cached ETag
        case ObjectStoreX.get(store, path, if_none_match: cached_etag) do
          {:error, :not_modified} ->
            # Cache hit - content unchanged
            increment_stat(stats_table, :hits)
            {:ok, cached_data, :hit}

          {:ok, new_data, meta} ->
            # Content changed - update cache
            update_cache(cache_table, path, meta.etag, new_data)
            increment_stat(stats_table, :misses)
            {:ok, new_data, :miss}

          {:error, reason} ->
            {:error, reason}
        end

      :not_found ->
        # Cache miss - fetch and cache
        case ObjectStoreX.get(store, path) do
          {:ok, data} ->
            {:ok, meta} = ObjectStoreX.head(store, path)
            update_cache(cache_table, path, meta.etag, data)
            increment_stat(stats_table, :misses)
            {:ok, data, :miss}

          {:error, reason} ->
            {:error, reason}
        end
    end
  rescue
    _ ->
      # Handle cleanup errors
      :ok
  end

  @doc """
  Invalidates (removes) a cache entry.

  ## Parameters

    - `cache` - Cache reference
    - `path` - Object path to invalidate

  ## Returns

    - `:ok`

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> HTTPCache.invalidate(cache, "file.txt")
      :ok
  """
  @spec invalidate(cache_ref(), String.t()) :: :ok
  def invalidate(cache, path) do
    stats_table = derive_stats_table(cache)
    :ets.delete(cache, path)
    increment_stat(stats_table, :invalidations)
    :ok
  end

  @doc """
  Clears all entries from the cache.

  ## Parameters

    - `cache` - Cache reference

  ## Returns

    - `:ok`

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> HTTPCache.clear(cache)
      :ok
  """
  @spec clear(cache_ref()) :: :ok
  def clear(cache) do
    :ets.delete_all_objects(cache)
    :ok
  end

  @doc """
  Retrieves cache statistics.

  ## Parameters

    - `cache` - Cache reference

  ## Returns

    - Map with statistics: `%{hits: n, misses: n, entries: n, invalidations: n}`

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> HTTPCache.stats(cache)
      %{hits: 0, misses: 0, entries: 0, invalidations: 0}
  """
  @spec stats(cache_ref()) :: map()
  def stats(cache) do
    stats_table = derive_stats_table(cache)
    entries = :ets.info(cache, :size) || 0

    %{
      hits: get_stat(stats_table, :hits),
      misses: get_stat(stats_table, :misses),
      entries: entries,
      invalidations: get_stat(stats_table, :invalidations),
      hit_rate: calculate_hit_rate(stats_table)
    }
  end

  @doc """
  Fetches data with conditional headers based on cache state.

  This is a lower-level function that demonstrates using both
  `if_none_match` (ETag) and `if_modified_since` (timestamp) conditions.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `path` - Object path
    - `cache` - Cache reference
    - `opts` - Optional keyword list:
      - `:use_modified_since` - Also check modification time (default: false)

  ## Returns

    - `{:ok, data, :hit}` - Cache hit
    - `{:ok, data, :miss}` - Cache miss or updated
    - `{:error, reason}` - Error

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> ObjectStoreX.put(store, "data", "value")
      iex> HTTPCache.get_with_conditions(store, "data", cache, use_modified_since: true)
      {:ok, "value", :miss}
  """
  @spec get_with_conditions(ObjectStoreX.store(), String.t(), cache_ref(), keyword()) ::
          cache_result()
  def get_with_conditions(store, path, cache, opts \\ []) do
    use_modified_since = Keyword.get(opts, :use_modified_since, false)
    cache_table = cache
    stats_table = derive_stats_table(cache)

    case lookup_cache_with_timestamp(cache_table, path) do
      {:ok, cached_etag, cached_data, timestamp} ->
        get_opts =
          if use_modified_since do
            [if_none_match: cached_etag, if_modified_since: timestamp]
          else
            [if_none_match: cached_etag]
          end

        case ObjectStoreX.get(store, path, get_opts) do
          {:error, :not_modified} ->
            increment_stat(stats_table, :hits)
            {:ok, cached_data, :hit}

          {:ok, new_data, meta} ->
            update_cache_with_timestamp(cache_table, path, meta.etag, new_data, meta.last_modified)
            increment_stat(stats_table, :misses)
            {:ok, new_data, :miss}

          {:error, reason} ->
            {:error, reason}
        end

      :not_found ->
        case ObjectStoreX.get(store, path) do
          {:ok, data} ->
            {:ok, meta} = ObjectStoreX.head(store, path)
            update_cache_with_timestamp(cache_table, path, meta.etag, data, meta.last_modified)
            increment_stat(stats_table, :misses)
            {:ok, data, :miss}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @doc """
  Stops and destroys the cache.

  ## Parameters

    - `cache` - Cache reference

  ## Returns

    - `:ok`

  ## Examples

      iex> {:ok, cache} = HTTPCache.start_cache("test")
      iex> HTTPCache.stop_cache(cache)
      :ok
  """
  @spec stop_cache(cache_ref()) :: :ok
  def stop_cache(cache) do
    stats_table = derive_stats_table(cache)

    try do
      :ets.delete(cache)
      :ets.delete(stats_table)
    rescue
      ArgumentError -> :ok
    end

    :ok
  end

  # Private helpers

  defp cache_table_name(name) when is_binary(name) do
    String.to_atom("http_cache_#{name}")
  end

  defp cache_table_name(name) when is_atom(name) do
    String.to_atom("http_cache_#{name}")
  end

  defp stats_table_name(name) when is_binary(name) do
    String.to_atom("http_cache_stats_#{name}")
  end

  defp stats_table_name(name) when is_atom(name) do
    String.to_atom("http_cache_stats_#{name}")
  end

  defp derive_stats_table(cache_table) do
    # Convert cache table name to stats table name
    table_info = :ets.info(cache_table)

    if table_info == :undefined or table_info == nil do
      :http_cache_stats_default
    else
      cache_name = Keyword.get(table_info, :name, nil)

      if cache_name && is_atom(cache_name) do
        cache_str = Atom.to_string(cache_name)
        stats_str = String.replace(cache_str, "http_cache_", "http_cache_stats_")
        String.to_atom(stats_str)
      else
        # Fallback for unnamed tables
        :http_cache_stats_default
      end
    end
  end

  defp lookup_cache(cache_table, path) do
    case :ets.lookup(cache_table, path) do
      [{^path, etag, data}] -> {:ok, etag, data}
      [{^path, etag, data, _timestamp}] -> {:ok, etag, data}
      [] -> :not_found
    end
  end

  defp lookup_cache_with_timestamp(cache_table, path) do
    case :ets.lookup(cache_table, path) do
      [{^path, etag, data, timestamp}] -> {:ok, etag, data, timestamp}
      [{^path, etag, data}] -> {:ok, etag, data, nil}
      [] -> :not_found
    end
  end

  defp update_cache(cache_table, path, etag, data) do
    :ets.insert(cache_table, {path, etag, data})
  end

  defp update_cache_with_timestamp(cache_table, path, etag, data, timestamp) do
    :ets.insert(cache_table, {path, etag, data, timestamp})
  end

  defp increment_stat(stats_table, key) do
    try do
      :ets.update_counter(stats_table, key, {2, 1})
    rescue
      ArgumentError ->
        :ets.insert(stats_table, {key, 1})
        1
    end
  end

  defp get_stat(stats_table, key) do
    case :ets.lookup(stats_table, key) do
      [{^key, value}] -> value
      [] -> 0
    end
  end

  defp calculate_hit_rate(stats_table) do
    hits = get_stat(stats_table, :hits)
    misses = get_stat(stats_table, :misses)
    total = hits + misses

    if total > 0 do
      Float.round(hits / total * 100, 2)
    else
      0.0
    end
  end
end
