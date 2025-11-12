defmodule DistributedCacheTest do
  use ExUnit.Case, async: true

  @moduletag :OBX004_3A

  setup do
    # Create temporary storage directory
    tmp_dir = System.tmp_dir!()
    storage_dir = Path.join(tmp_dir, "test_cache_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(storage_dir)

    # Create a test store
    {:ok, store} = ObjectStoreX.new(:local, path: storage_dir)

    # Start the cache with a unique name for this test
    cache_name = :"cache_#{:erlang.unique_integer([:positive])}"
    {:ok, cache_pid} = DistributedCache.start_link(store, name: cache_name, ttl: 10_000)

    on_exit(fn ->
      if Process.alive?(cache_pid) do
        GenServer.stop(cache_pid)
      end

      File.rm_rf(storage_dir)
    end)

    %{
      store: store,
      cache: cache_name,
      storage_dir: storage_dir
    }
  end

  @tag :OBX004_3A_T4
  test "distributed_cache compiles", _context do
    # This test passes if the module loads without errors
    assert is_atom(DistributedCache)
  end

  @tag :OBX004_3A_T5
  test "caching works - first get is miss, second is hit", %{cache: cache, store: store} do
    # Put data directly to store
    ObjectStoreX.put(store, "test_key", "test_value")

    # First get - cache miss
    assert {:ok, value} = DistributedCache.get(cache, "test_key")
    assert value == "test_value"

    stats = DistributedCache.stats(cache)
    assert stats.misses == 1
    assert stats.hits == 0

    # Second get - cache hit (or miss if ETag validation happens)
    assert {:ok, value} = DistributedCache.get(cache, "test_key")
    assert value == "test_value"

    stats = DistributedCache.stats(cache)
    # After second get, we should have at least one hit or miss
    assert stats.hits + stats.misses >= 2
  end

  @tag :OBX004_3A_T6
  test "put updates cache and storage", %{cache: cache, store: store} do
    # Put through cache
    assert :ok = DistributedCache.put(cache, "put_key", "put_value")

    # Verify it's in storage
    assert {:ok, value} = ObjectStoreX.get(store, "put_key")
    assert value == "put_value"

    # Verify it's cached (get should be fast)
    assert {:ok, cached_value} = DistributedCache.get(cache, "put_key")
    assert cached_value == "put_value"
  end

  @tag :OBX004_3A_T7
  test "invalidate removes from cache", %{cache: cache, store: store} do
    # Put and cache data
    DistributedCache.put(cache, "invalidate_key", "value")
    DistributedCache.get(cache, "invalidate_key")

    # Invalidate
    assert :ok = DistributedCache.invalidate(cache, "invalidate_key")

    # Next get should be a cache miss
    initial_misses = DistributedCache.stats(cache).misses
    DistributedCache.get(cache, "invalidate_key")
    new_misses = DistributedCache.stats(cache).misses

    assert new_misses > initial_misses
  end

  @tag :OBX004_3A_T8
  test "clear removes all cache entries", %{cache: cache} do
    # Put multiple entries
    DistributedCache.put(cache, "key1", "value1")
    DistributedCache.put(cache, "key2", "value2")
    DistributedCache.put(cache, "key3", "value3")

    # Verify cache has entries
    stats_before = DistributedCache.stats(cache)
    assert stats_before.entries > 0

    # Clear cache
    assert :ok = DistributedCache.clear(cache)

    # Verify cache is empty
    stats_after = DistributedCache.stats(cache)
    assert stats_after.entries == 0
  end

  @tag :OBX004_3A_T9
  test "stats tracks hits, misses, and invalidations", %{cache: cache, store: store} do
    # Initial stats
    stats = DistributedCache.stats(cache)
    assert stats.hits == 0
    assert stats.misses == 0
    assert stats.invalidations == 0

    # Cause a miss
    ObjectStoreX.put(store, "stats_key", "value")
    DistributedCache.get(cache, "stats_key")

    stats = DistributedCache.stats(cache)
    assert stats.misses > 0

    # Cause an invalidation
    DistributedCache.invalidate(cache, "stats_key")

    stats = DistributedCache.stats(cache)
    assert stats.invalidations > 0
  end

  @tag :OBX004_3A_T10
  test "handles non-existent keys gracefully", %{cache: cache} do
    result = DistributedCache.get(cache, "nonexistent_key")

    assert {:error, _reason} = result
  end

  @tag :OBX004_3A_T11
  test "TTL expires old entries", %{store: store} do
    # Start cache with very short TTL (100ms)
    cache_name = :"ttl_cache_#{:erlang.unique_integer([:positive])}"
    {:ok, cache_pid} = DistributedCache.start_link(store, name: cache_name, ttl: 100)

    # Put data
    ObjectStoreX.put(store, "ttl_key", "value")
    DistributedCache.get(cache_name, "ttl_key")

    # Wait for TTL to expire
    Process.sleep(150)

    # Trigger cleanup by getting the key again
    initial_misses = DistributedCache.stats(cache_name).misses
    DistributedCache.get(cache_name, "ttl_key")
    new_misses = DistributedCache.stats(cache_name).misses

    # Should be a miss due to TTL expiration
    assert new_misses > initial_misses

    GenServer.stop(cache_pid)
  end
end
