defmodule ObjectStoreX.Examples.DistributedLock do
  @moduledoc """
  Distributed locking implementation using object storage with create-only semantics.

  This module demonstrates how to implement distributed locks using ObjectStoreX's
  `:create` put mode. The lock acquisition is atomic - only one process can successfully
  create a lock file at a time.

  ## Features

  - Atomic lock acquisition using `:create` mode
  - Lock metadata (holder, timestamp)
  - Lock staleness detection
  - Safe lock release

  ## Example

      {:ok, store} = ObjectStoreX.new(:memory)

      # Acquire lock
      case DistributedLock.acquire(store, "resource-123") do
        {:ok, lock_info} ->
          IO.puts("Lock acquired!")
          # Do work...
          DistributedLock.release(store, "resource-123")

        {:error, :locked} ->
          IO.puts("Resource is locked by another process")
      end

  ## Use Cases

  - Distributed task coordination
  - Leader election
  - Resource access control
  - Preventing concurrent modifications
  """

  @type lock_info :: %{
          holder: node(),
          timestamp: integer(),
          acquired_at: DateTime.t()
        }

  @doc """
  Attempts to acquire a distributed lock for the given resource.

  Uses ObjectStoreX's `:create` mode to ensure atomic acquisition.
  Only succeeds if no lock currently exists.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `resource` - Resource identifier to lock
    - `opts` - Optional keyword list:
      - `:metadata` - Additional metadata to store with lock (default: %{})

  ## Returns

    - `{:ok, lock_info}` - Lock acquired successfully
    - `{:error, :locked}` - Lock already held by another process
    - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> DistributedLock.acquire(store, "task-1")
      {:ok, %{holder: :nonode@nohost, timestamp: 1699999999, ...}}

      iex> # Second acquisition fails
      iex> DistributedLock.acquire(store, "task-1")
      {:error, :locked}
  """
  @spec acquire(ObjectStoreX.store(), String.t(), keyword()) ::
          {:ok, lock_info()} | {:error, atom()}
  def acquire(store, resource, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    lock_data = %{
      holder: Atom.to_string(node()),
      timestamp: System.system_time(:second),
      acquired_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      metadata: metadata
    }

    lock_path = lock_path(resource)
    json_data = Jason.encode!(lock_data)

    case ObjectStoreX.put(store, lock_path, json_data, mode: :create) do
      {:ok, _result} ->
        {:ok, lock_data}

      {:error, :already_exists} ->
        {:error, :locked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Releases a distributed lock for the given resource.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `resource` - Resource identifier to unlock

  ## Returns

    - `:ok` - Lock released successfully
    - `{:error, reason}` - Error releasing lock

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> DistributedLock.acquire(store, "task-1")
      iex> DistributedLock.release(store, "task-1")
      :ok
  """
  @spec release(ObjectStoreX.store(), String.t()) :: :ok | {:error, atom()}
  def release(store, resource) do
    lock_path = lock_path(resource)
    ObjectStoreX.delete(store, lock_path)
  end

  @doc """
  Checks if a lock exists and retrieves its information.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `resource` - Resource identifier to check

  ## Returns

    - `{:ok, lock_info}` - Lock exists with information
    - `{:error, :not_locked}` - No lock exists
    - `{:error, reason}` - Error checking lock

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> DistributedLock.check(store, "task-1")
      {:error, :not_locked}

      iex> DistributedLock.acquire(store, "task-1")
      iex> {:ok, info} = DistributedLock.check(store, "task-1")
      iex> info.holder
      :nonode@nohost
  """
  @spec check(ObjectStoreX.store(), String.t()) ::
          {:ok, lock_info()} | {:error, atom()}
  def check(store, resource) do
    lock_path = lock_path(resource)

    case ObjectStoreX.get(store, lock_path) do
      {:ok, data} ->
        case Jason.decode(data, keys: :atoms) do
          {:ok, lock_info} -> {:ok, lock_info}
          {:error, _} -> {:error, :invalid_lock_data}
        end

      {:error, :not_found} ->
        {:error, :not_locked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Checks if a lock is stale (older than specified max age) and optionally forces release.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `resource` - Resource identifier to check
    - `max_age_seconds` - Maximum lock age in seconds (default: 300)
    - `opts` - Optional keyword list:
      - `:force_release` - If true, automatically release stale locks (default: false)

  ## Returns

    - `{:ok, :fresh}` - Lock exists and is not stale
    - `{:ok, :stale}` - Lock is stale
    - `{:ok, :released}` - Stale lock was force-released
    - `{:error, :not_locked}` - No lock exists
    - `{:error, reason}` - Error checking lock

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> DistributedLock.acquire(store, "task-1")
      iex> DistributedLock.check_staleness(store, "task-1", 300)
      {:ok, :fresh}

      iex> # After 301 seconds...
      iex> DistributedLock.check_staleness(store, "task-1", 300, force_release: true)
      {:ok, :released}
  """
  @spec check_staleness(ObjectStoreX.store(), String.t(), non_neg_integer(), keyword()) ::
          {:ok, :fresh | :stale | :released} | {:error, atom()}
  def check_staleness(store, resource, max_age_seconds \\ 300, opts \\ []) do
    force_release = Keyword.get(opts, :force_release, false)

    case check(store, resource) do
      {:ok, lock_info} ->
        current_time = System.system_time(:second)
        lock_age = current_time - lock_info.timestamp

        if lock_age > max_age_seconds do
          if force_release do
            case release(store, resource) do
              :ok -> {:ok, :released}
              error -> error
            end
          else
            {:ok, :stale}
          end
        else
          {:ok, :fresh}
        end

      {:error, :not_locked} ->
        {:error, :not_locked}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Attempts to acquire a lock with retries and exponential backoff.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `resource` - Resource identifier to lock
    - `opts` - Optional keyword list:
      - `:max_retries` - Maximum number of retry attempts (default: 5)
      - `:initial_delay_ms` - Initial delay in milliseconds (default: 100)
      - `:max_delay_ms` - Maximum delay in milliseconds (default: 5000)
      - `:metadata` - Additional metadata for lock

  ## Returns

    - `{:ok, lock_info}` - Lock acquired successfully
    - `{:error, :max_retries_exceeded}` - Failed after max retries
    - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> DistributedLock.acquire_with_retry(store, "task-1", max_retries: 3)
      {:ok, %{holder: :nonode@nohost, ...}}
  """
  @spec acquire_with_retry(ObjectStoreX.store(), String.t(), keyword()) ::
          {:ok, lock_info()} | {:error, atom()}
  def acquire_with_retry(store, resource, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 5)
    initial_delay = Keyword.get(opts, :initial_delay_ms, 100)
    max_delay = Keyword.get(opts, :max_delay_ms, 5000)

    do_acquire_with_retry(store, resource, opts, 0, max_retries, initial_delay, max_delay)
  end

  defp do_acquire_with_retry(_store, _resource, _opts, attempt, max_retries, _delay, _max_delay)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp do_acquire_with_retry(store, resource, opts, attempt, max_retries, delay, max_delay) do
    case acquire(store, resource, opts) do
      {:ok, lock_info} ->
        {:ok, lock_info}

      {:error, :locked} ->
        # Exponential backoff with jitter
        current_delay = min(delay * :math.pow(2, attempt), max_delay)
        jitter = :rand.uniform(trunc(current_delay * 0.1))
        sleep_time = trunc(current_delay + jitter)

        Process.sleep(sleep_time)
        do_acquire_with_retry(store, resource, opts, attempt + 1, max_retries, delay, max_delay)

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Private helpers

  defp lock_path(resource) do
    "locks/#{resource}"
  end
end
