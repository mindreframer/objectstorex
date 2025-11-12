# Distributed Systems Guide

This guide covers using ObjectStoreX for distributed systems patterns including locks, Compare-And-Swap (CAS), and HTTP-style caching.

## Table of Contents

- [Distributed Locks](#distributed-locks)
- [Compare-And-Swap (CAS)](#compare-and-swap-cas)
- [HTTP-Style Caching](#http-style-caching)
- [Atomic Operations](#atomic-operations)
- [Distributed Cache Example](#distributed-cache-example)
- [Leader Election](#leader-election)
- [Best Practices](#best-practices)

## Distributed Locks

Use create-only writes to implement distributed locks across multiple nodes.

### Basic Lock Acquisition

```elixir
defmodule DistributedLock do
  @lock_ttl 60_000  # 60 seconds

  def acquire(store, lock_name, owner_id) do
    lock_path = "locks/#{lock_name}"
    lock_data = %{
      owner: owner_id,
      acquired_at: DateTime.utc_now() |> DateTime.to_iso8601()
    } |> Jason.encode!()

    case ObjectStoreX.put(store, lock_path, lock_data, mode: :create) do
      {:ok, _meta} ->
        {:ok, :acquired}

      {:error, :already_exists} ->
        {:error, :locked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def release(store, lock_name) do
    lock_path = "locks/#{lock_name}"
    ObjectStoreX.delete(store, lock_path)
  end

  def with_lock(store, lock_name, owner_id, timeout \\ 30_000, func) do
    case acquire(store, lock_name, owner_id) do
      {:ok, :acquired} ->
        try do
          func.()
        after
          release(store, lock_name)
        end

      {:error, :locked} ->
        if timeout > 0 do
          :timer.sleep(1000)
          with_lock(store, lock_name, owner_id, timeout - 1000, func)
        else
          {:error, :timeout}
        end
    end
  end
end

# Usage
DistributedLock.with_lock(store, "process-data", "node-1", fn ->
  # Critical section - only one node executes at a time
  process_data()
end)
```

### Lock with TTL

```elixir
defmodule TTLLock do
  def acquire(store, lock_name, owner_id, ttl_seconds \\ 60) do
    lock_path = "locks/#{lock_name}"
    expires_at = DateTime.utc_now() |> DateTime.add(ttl_seconds, :second)

    lock_data = %{
      owner: owner_id,
      acquired_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      expires_at: DateTime.to_iso8601(expires_at)
    } |> Jason.encode!()

    case ObjectStoreX.put(store, lock_path, lock_data, mode: :create) do
      {:ok, _meta} -> {:ok, :acquired}
      {:error, :already_exists} -> try_steal_expired_lock(store, lock_path, owner_id, ttl_seconds)
    end
  end

  defp try_steal_expired_lock(store, lock_path, owner_id, ttl_seconds) do
    case ObjectStoreX.get(store, lock_path) do
      {:ok, data} ->
        lock_info = Jason.decode!(data)
        expires_at = DateTime.from_iso8601(lock_info["expires_at"]) |> elem(1)

        if DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
          # Lock expired, delete and retry
          ObjectStoreX.delete(store, lock_path)
          acquire(store, lock_name, owner_id, ttl_seconds)
        else
          {:error, :locked}
        end

      {:error, :not_found} ->
        # Lock was released, retry
        acquire(store, lock_name, owner_id, ttl_seconds)
    end
  end
end
```

### Lock with Auto-Renewal

```elixir
defmodule RenewableLock do
  use GenServer

  def start_link(store, lock_name, owner_id) do
    GenServer.start_link(__MODULE__, {store, lock_name, owner_id})
  end

  def init({store, lock_name, owner_id}) do
    case DistributedLock.acquire(store, lock_name, owner_id) do
      {:ok, :acquired} ->
        schedule_renewal()
        {:ok, %{store: store, lock_name: lock_name, owner_id: owner_id}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  def handle_info(:renew, state) do
    # Renew by updating last_modified
    lock_path = "locks/#{state.lock_name}"
    {:ok, data} = ObjectStoreX.get(state.store, lock_path)
    ObjectStoreX.put(state.store, lock_path, data)

    schedule_renewal()
    {:noreply, state}
  end

  defp schedule_renewal do
    Process.send_after(self(), :renew, 30_000)  # Renew every 30s
  end

  def terminate(_reason, state) do
    DistributedLock.release(state.store, state.lock_name)
  end
end
```

## Compare-And-Swap (CAS)

Implement optimistic locking for concurrent updates.

### Basic CAS Pattern

```elixir
defmodule Counter do
  def increment(store, counter_path) do
    case ObjectStoreX.get(store, counter_path) do
      {:ok, data} ->
        {:ok, meta} = ObjectStoreX.head(store, counter_path)
        current_value = String.to_integer(data)
        new_value = current_value + 1

        # Try to update with ETag check
        case ObjectStoreX.put(store, counter_path, to_string(new_value),
                              mode: {:update, %{etag: meta[:etag]}}) do
          {:ok, _meta} -> {:ok, new_value}
          {:error, :precondition_failed} -> increment(store, counter_path)  # Retry
        end

      {:error, :not_found} ->
        # Initialize counter
        case ObjectStoreX.put(store, counter_path, "1", mode: :create) do
          {:ok, _meta} -> {:ok, 1}
          {:error, :already_exists} -> increment(store, counter_path)  # Someone else created it
        end
    end
  end
end

# Usage
{:ok, new_count} = Counter.increment(store, "counters/requests")
```

### CAS with JSON Data

```elixir
defmodule JSONDocument do
  def update(store, path, update_fn, max_retries \\ 10) do
    update_with_retry(store, path, update_fn, max_retries)
  end

  defp update_with_retry(store, path, update_fn, retries) when retries > 0 do
    case ObjectStoreX.get(store, path) do
      {:ok, json_data} ->
        {:ok, meta} = ObjectStoreX.head(store, path)
        doc = Jason.decode!(json_data)
        updated_doc = update_fn.(doc)
        new_json = Jason.encode!(updated_doc)

        case ObjectStoreX.put(store, path, new_json,
                              mode: {:update, %{etag: meta[:etag]}}) do
          {:ok, _meta} -> {:ok, updated_doc}
          {:error, :precondition_failed} ->
            :timer.sleep(10)  # Brief backoff
            update_with_retry(store, path, update_fn, retries - 1)
        end

      {:error, :not_found} ->
        # Initialize document
        initial_doc = update_fn.(%{})
        json = Jason.encode!(initial_doc)

        case ObjectStoreX.put(store, path, json, mode: :create) do
          {:ok, _meta} -> {:ok, initial_doc}
          {:error, :already_exists} ->
            update_with_retry(store, path, update_fn, retries - 1)
        end
    end
  end

  defp update_with_retry(_store, _path, _update_fn, 0) do
    {:error, :too_many_retries}
  end
end

# Usage
JSONDocument.update(store, "config.json", fn config ->
  Map.update(config, "requests", 1, &(&1 + 1))
end)
```

## HTTP-Style Caching

Use ETags for efficient cache validation.

### Basic Cache Validation

```elixir
defmodule HTTPCache do
  def get_with_cache(store, path, cached_etag \\ nil) do
    if cached_etag do
      case ObjectStoreX.get(store, path, if_none_match: cached_etag) do
        {:ok, data, meta} ->
          # Object was modified, cache stale
          {:modified, data, meta[:etag]}

        {:error, :not_modified} ->
          # Cache is still valid
          :not_modified
      end
    else
      # No cached version, fetch fresh
      {:ok, data, meta} = ObjectStoreX.get(store, path)
      {:ok, data, meta[:etag]}
    end
  end
end

# Usage
case HTTPCache.get_with_cache(store, "data.json", cached_etag) do
  {:modified, data, new_etag} ->
    # Update cache
    Cache.put("data.json", data, new_etag)
    data

  :not_modified ->
    # Use cached version
    Cache.get("data.json")

  {:ok, data, etag} ->
    # First fetch, populate cache
    Cache.put("data.json", data, etag)
    data
end
```

### GenServer-Based Cache

```elixir
defmodule DistributedCache do
  use GenServer

  def start_link(store) do
    GenServer.start_link(__MODULE__, store, name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def init(store) do
    cache = :ets.new(:cache, [:set, :private])
    {:ok, %{store: store, cache: cache}}
  end

  def handle_call({:get, key}, _from, state) do
    result = case :ets.lookup(state.cache, key) do
      [{^key, data, etag, _timestamp}] ->
        # Try conditional get
        case ObjectStoreX.get(state.store, key, if_none_match: etag) do
          {:error, :not_modified} ->
            # Cache hit!
            {:ok, data}

          {:ok, new_data, meta} ->
            # Cache miss, update cache
            :ets.insert(state.cache, {key, new_data, meta[:etag], System.system_time()})
            {:ok, new_data}

          {:error, reason} ->
            {:error, reason}
        end

      [] ->
        # Not in cache, fetch fresh
        case ObjectStoreX.get(state.store, key) do
          {:ok, data, meta} ->
            :ets.insert(state.cache, {key, data, meta[:etag], System.system_time()})
            {:ok, data}

          {:error, reason} ->
            {:error, reason}
        end
    end

    {:reply, result, state}
  end
end
```

## Atomic Operations

Use atomic copy operations for safe file operations.

### Atomic Backup

```elixir
defmodule AtomicBackup do
  def create_backup(store, source_path) do
    backup_path = "#{source_path}.backup"

    case ObjectStoreX.copy_if_not_exists(store, source_path, backup_path) do
      :ok ->
        {:ok, backup_path}

      {:error, :already_exists} ->
        # Backup already exists, create versioned backup
        timestamp = DateTime.utc_now() |> DateTime.to_unix()
        versioned_path = "#{source_path}.backup.#{timestamp}"
        ObjectStoreX.copy(store, source_path, versioned_path)
        {:ok, versioned_path}

      {:error, :not_supported} ->
        # Fallback for S3: manual check-then-copy
        manual_backup(store, source_path, backup_path)
    end
  end

  defp manual_backup(store, source_path, backup_path) do
    case ObjectStoreX.head(store, backup_path) do
      {:error, :not_found} ->
        ObjectStoreX.copy(store, source_path, backup_path)

      {:ok, _meta} ->
        {:error, :already_exists}
    end
  end
end
```

### Safe Rename

```elixir
defmodule SafeRename do
  def rename(store, old_path, new_path) do
    case ObjectStoreX.rename_if_not_exists(store, old_path, new_path) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        {:error, :destination_exists}

      {:error, :not_supported} ->
        # Fallback: manual check-then-rename
        case ObjectStoreX.head(store, new_path) do
          {:error, :not_found} ->
            ObjectStoreX.rename(store, old_path, new_path)

          {:ok, _meta} ->
            {:error, :destination_exists}
        end
    end
  end
end
```

## Distributed Cache Example

Complete example of a distributed cache with ETag validation.

```elixir
defmodule MyApp.DistributedCache do
  use GenServer

  @cache_ttl 300_000  # 5 minutes

  def start_link(store) do
    GenServer.start_link(__MODULE__, store, name: __MODULE__)
  end

  def get(key) do
    GenServer.call(__MODULE__, {:get, key})
  end

  def put(key, value) do
    GenServer.cast(__MODULE__, {:put, key, value})
  end

  def invalidate(key) do
    GenServer.cast(__MODULE__, {:invalidate, key})
  end

  def init(store) do
    cache = :ets.new(:cache, [:set, :private])
    schedule_cleanup()
    {:ok, %{store: store, cache: cache}}
  end

  def handle_call({:get, key}, _from, state) do
    result = case :ets.lookup(state.cache, key) do
      [{^key, data, etag, timestamp}] ->
        if System.system_time(:millisecond) - timestamp < @cache_ttl do
          validate_cache(state.store, state.cache, key, data, etag, timestamp)
        else
          # Cache expired, fetch fresh
          fetch_fresh(state.store, state.cache, key)
        end

      [] ->
        fetch_fresh(state.store, state.cache, key)
    end

    {:reply, result, state}
  end

  def handle_cast({:put, key, value}, state) do
    json = Jason.encode!(value)
    ObjectStoreX.put(state.store, key, json)
    :ets.delete(state.cache, key)  # Invalidate cache
    {:noreply, state}
  end

  def handle_cast({:invalidate, key}, state) do
    :ets.delete(state.cache, key)
    {:noreply, state}
  end

  def handle_info(:cleanup, state) do
    now = System.system_time(:millisecond)

    :ets.select_delete(state.cache, [
      {{:"$1", :"$2", :"$3", :"$4"},
       [{:<, {:-, now, :"$4"}, @cache_ttl}],
       [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp validate_cache(store, cache, key, data, etag, timestamp) do
    case ObjectStoreX.get(store, key, if_none_match: etag) do
      {:error, :not_modified} ->
        # Cache valid
        {:ok, Jason.decode!(data)}

      {:ok, new_data, meta} ->
        # Cache stale, update
        :ets.insert(cache, {key, new_data, meta[:etag], System.system_time(:millisecond)})
        {:ok, Jason.decode!(new_data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp fetch_fresh(store, cache, key) do
    case ObjectStoreX.get(store, key) do
      {:ok, data, meta} ->
        :ets.insert(cache, {key, data, meta[:etag], System.system_time(:millisecond)})
        {:ok, Jason.decode!(data)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)  # Cleanup every minute
  end
end
```

## Leader Election

Implement leader election using create-only writes.

```elixir
defmodule LeaderElection do
  use GenServer

  def start_link(store, node_id) do
    GenServer.start_link(__MODULE__, {store, node_id}, name: __MODULE__)
  end

  def is_leader? do
    GenServer.call(__MODULE__, :is_leader?)
  end

  def init({store, node_id}) do
    send(self(), :try_become_leader)
    {:ok, %{store: store, node_id: node_id, is_leader: false}}
  end

  def handle_info(:try_become_leader, state) do
    leader_data = %{
      node_id: state.node_id,
      elected_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      heartbeat: DateTime.utc_now() |> DateTime.to_iso8601()
    } |> Jason.encode!()

    is_leader = case ObjectStoreX.put(state.store, "leader", leader_data, mode: :create) do
      {:ok, _meta} ->
        # We became leader!
        schedule_heartbeat()
        true

      {:error, :already_exists} ->
        # Someone else is leader
        schedule_retry()
        false
    end

    {:noreply, %{state | is_leader: is_leader}}
  end

  def handle_info(:heartbeat, state) do
    if state.is_leader do
      # Update heartbeat
      {:ok, data} = ObjectStoreX.get(state.store, "leader")
      leader_info = Jason.decode!(data)
      updated = Map.put(leader_info, "heartbeat", DateTime.utc_now() |> DateTime.to_iso8601())
      ObjectStoreX.put(state.store, "leader", Jason.encode!(updated))

      schedule_heartbeat()
    end

    {:noreply, state}
  end

  def handle_call(:is_leader?, _from, state) do
    {:reply, state.is_leader, state}
  end

  defp schedule_heartbeat do
    Process.send_after(self(), :heartbeat, 10_000)  # Every 10s
  end

  defp schedule_retry do
    Process.send_after(self(), :try_become_leader, 30_000)  # Try again in 30s
  end
end
```

## Best Practices

### 1. Handle Retry Loops

```elixir
# Always limit retries to prevent infinite loops
def cas_update(store, path, update_fn, max_retries \\ 10) do
  if max_retries > 0 do
    # ... CAS logic ...
    case result do
      {:error, :precondition_failed} ->
        cas_update(store, path, update_fn, max_retries - 1)
      other ->
        other
    end
  else
    {:error, :too_many_retries}
  end
end
```

### 2. Use Exponential Backoff

```elixir
defp backoff(attempt) do
  base_delay = 100  # 100ms
  max_delay = 10_000  # 10s
  delay = min(base_delay * :math.pow(2, attempt), max_delay)
  :timer.sleep(trunc(delay))
end
```

### 3. Monitor Lock Expiration

```elixir
# Always set TTLs on locks
# Always implement lock renewal for long operations
# Always clean up expired locks
```

### 4. Use Appropriate Consistency Model

```elixir
# Strong consistency: Use CAS with ETags
# Eventual consistency: Use timestamps and LWW (Last-Write-Wins)
```

## Next Steps

- [Getting Started Guide](getting_started.md)
- [Configuration Guide](configuration.md)
- [Streaming Guide](streaming.md)
- [Error Handling Guide](error_handling.md)
