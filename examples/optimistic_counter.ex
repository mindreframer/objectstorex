defmodule ObjectStoreX.Examples.OptimisticCounter do
  @moduledoc """
  Optimistic locking implementation using Compare-And-Swap (CAS) operations.

  This module demonstrates how to implement optimistic concurrency control using
  ObjectStoreX's CAS operations with ETags. Multiple processes can safely update
  the same counter without distributed locks by using version-based updates.

  ## Features

  - Compare-And-Swap with automatic retry
  - ETags for version tracking
  - Configurable retry strategies
  - Safe concurrent updates

  ## Example

      {:ok, store} = ObjectStoreX.new(:memory)

      # Initialize counter
      OptimisticCounter.initialize(store, "counter-1", 0)

      # Increment counter (with automatic retry on conflict)
      {:ok, new_value} = OptimisticCounter.increment(store, "counter-1")
      # => 1

      # Multiple processes can safely increment concurrently
      tasks = for _ <- 1..10 do
        Task.async(fn -> OptimisticCounter.increment(store, "counter-1") end)
      end
      Task.await_many(tasks)

      {:ok, value} = OptimisticCounter.get(store, "counter-1")
      # => 11 (initial 0 + 10 increments + 1 increment = 11)

  ## Use Cases

  - Distributed counters (views, downloads, etc.)
  - Optimistic updates to shared state
  - Inventory management
  - Collaborative editing with conflict detection
  """

  require Logger

  @type counter_value :: integer()

  @doc """
  Initializes a counter with a starting value.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `key` - Counter identifier
    - `initial_value` - Starting counter value (default: 0)

  ## Returns

    - `{:ok, result}` - Counter initialized successfully
    - `{:error, reason}` - Error initializing counter

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> OptimisticCounter.initialize(store, "downloads", 0)
      {:ok, %{etag: "...", version: nil}}
  """
  @spec initialize(ObjectStoreX.store(), String.t(), counter_value()) ::
          {:ok, map()} | {:error, atom()}
  def initialize(store, key, initial_value \\ 0) when is_integer(initial_value) do
    counter_path = counter_path(key)
    json_data = Jason.encode!(initial_value)
    ObjectStoreX.put(store, counter_path, json_data)
  end

  @doc """
  Gets the current counter value.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `key` - Counter identifier

  ## Returns

    - `{:ok, value}` - Current counter value
    - `{:error, reason}` - Error getting counter

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> OptimisticCounter.initialize(store, "views", 42)
      iex> OptimisticCounter.get(store, "views")
      {:ok, 42}
  """
  @spec get(ObjectStoreX.store(), String.t()) ::
          {:ok, counter_value()} | {:error, atom()}
  def get(store, key) do
    counter_path = counter_path(key)

    case ObjectStoreX.get(store, counter_path) do
      {:ok, data} ->
        case Jason.decode(data) do
          {:ok, value} when is_integer(value) -> {:ok, value}
          _ -> {:error, :invalid_counter_data}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Increments the counter by the specified amount with CAS retry.

  Uses Compare-And-Swap to ensure atomic updates. Automatically retries
  on conflict with exponential backoff.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `key` - Counter identifier
    - `opts` - Optional keyword list:
      - `:amount` - Amount to increment by (default: 1)
      - `:max_retries` - Maximum retry attempts (default: 10)

  ## Returns

    - `{:ok, new_value}` - Counter incremented successfully
    - `{:error, :max_retries_exceeded}` - Failed after max retries
    - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> OptimisticCounter.initialize(store, "count", 0)
      iex> OptimisticCounter.increment(store, "count")
      {:ok, 1}

      iex> OptimisticCounter.increment(store, "count", amount: 5)
      {:ok, 6}
  """
  @spec increment(ObjectStoreX.store(), String.t(), keyword()) ::
          {:ok, counter_value()} | {:error, atom()}
  def increment(store, key, opts \\ []) do
    amount = Keyword.get(opts, :amount, 1)
    max_retries = Keyword.get(opts, :max_retries, 10)

    do_increment_with_retry(store, key, amount, 0, max_retries)
  end

  defp do_increment_with_retry(_store, _key, _amount, attempt, max_retries)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp do_increment_with_retry(store, key, amount, attempt, max_retries) do
    counter_path = counter_path(key)

    # Read current value with metadata
    with {:ok, data} <- ObjectStoreX.get(store, counter_path),
         {:ok, current_value} <- Jason.decode(data),
         {:ok, meta} <- ObjectStoreX.head(store, counter_path) do
      new_value = current_value + amount
      new_data = Jason.encode!(new_value)

      # Attempt CAS update
      case ObjectStoreX.put(store, counter_path, new_data,
             mode: {:update, %{etag: meta.etag, version: meta.version}}
           ) do
        {:ok, _result} ->
          {:ok, new_value}

        {:error, :precondition_failed} ->
          # Conflict - another process updated it. Retry with backoff
          if attempt < max_retries - 1 do
            backoff_delay = calculate_backoff(attempt)
            Process.sleep(backoff_delay)
            do_increment_with_retry(store, key, amount, attempt + 1, max_retries)
          else
            {:error, :max_retries_exceeded}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      error -> error
    end
  end

  @doc """
  Decrements the counter by the specified amount with CAS retry.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `key` - Counter identifier
    - `opts` - Optional keyword list:
      - `:amount` - Amount to decrement by (default: 1)
      - `:max_retries` - Maximum retry attempts (default: 10)
      - `:min_value` - Minimum allowed value (default: nil, no minimum)

  ## Returns

    - `{:ok, new_value}` - Counter decremented successfully
    - `{:error, :min_value_reached}` - Cannot decrement below minimum
    - `{:error, :max_retries_exceeded}` - Failed after max retries
    - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> OptimisticCounter.initialize(store, "stock", 10)
      iex> OptimisticCounter.decrement(store, "stock")
      {:ok, 9}

      iex> OptimisticCounter.decrement(store, "stock", min_value: 0)
      {:ok, 8}
  """
  @spec decrement(ObjectStoreX.store(), String.t(), keyword()) ::
          {:ok, counter_value()} | {:error, atom()}
  def decrement(store, key, opts \\ []) do
    amount = Keyword.get(opts, :amount, 1)
    max_retries = Keyword.get(opts, :max_retries, 10)
    min_value = Keyword.get(opts, :min_value)

    do_decrement_with_retry(store, key, amount, min_value, 0, max_retries)
  end

  defp do_decrement_with_retry(_store, _key, _amount, _min_value, attempt, max_retries)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp do_decrement_with_retry(store, key, amount, min_value, attempt, max_retries) do
    counter_path = counter_path(key)

    # Read current value with metadata
    with {:ok, data} <- ObjectStoreX.get(store, counter_path),
         {:ok, current_value} <- Jason.decode(data),
         {:ok, meta} <- ObjectStoreX.head(store, counter_path) do
      new_value = current_value - amount

      # Check minimum value constraint
      if min_value != nil and new_value < min_value do
        {:error, :min_value_reached}
      else
        new_data = Jason.encode!(new_value)

        # Attempt CAS update
        case ObjectStoreX.put(store, counter_path, new_data,
               mode: {:update, %{etag: meta.etag, version: meta.version}}
             ) do
          {:ok, _result} ->
            {:ok, new_value}

          {:error, :precondition_failed} ->
            # Conflict - retry with backoff
            if attempt < max_retries - 1 do
              backoff_delay = calculate_backoff(attempt)
              Process.sleep(backoff_delay)
              do_decrement_with_retry(store, key, amount, min_value, attempt + 1, max_retries)
            else
              {:error, :max_retries_exceeded}
            end

          {:error, reason} ->
            {:error, reason}
        end
      end
    else
      error -> error
    end
  end

  @doc """
  Updates the counter value using a custom function with CAS retry.

  Allows arbitrary transformations of the counter value while ensuring
  atomic updates with optimistic locking.

  ## Parameters

    - `store` - ObjectStoreX store reference
    - `key` - Counter identifier
    - `update_fn` - Function that takes current value and returns new value
    - `opts` - Optional keyword list:
      - `:max_retries` - Maximum retry attempts (default: 10)

  ## Returns

    - `{:ok, new_value}` - Counter updated successfully
    - `{:error, :max_retries_exceeded}` - Failed after max retries
    - `{:error, reason}` - Other errors

  ## Examples

      iex> {:ok, store} = ObjectStoreX.new(:memory)
      iex> OptimisticCounter.initialize(store, "value", 5)
      iex> OptimisticCounter.update(store, "value", fn v -> v * 2 end)
      {:ok, 10}

      iex> # Complex update
      iex> OptimisticCounter.update(store, "value", fn v -> max(v - 3, 0) end)
      {:ok, 7}
  """
  @spec update(ObjectStoreX.store(), String.t(), (counter_value() -> counter_value()), keyword()) ::
          {:ok, counter_value()} | {:error, atom()}
  def update(store, key, update_fn, opts \\ []) when is_function(update_fn, 1) do
    max_retries = Keyword.get(opts, :max_retries, 10)
    do_update_with_retry(store, key, update_fn, 0, max_retries)
  end

  defp do_update_with_retry(_store, _key, _update_fn, attempt, max_retries)
       when attempt >= max_retries do
    {:error, :max_retries_exceeded}
  end

  defp do_update_with_retry(store, key, update_fn, attempt, max_retries) do
    counter_path = counter_path(key)

    # Read current value with metadata
    with {:ok, data} <- ObjectStoreX.get(store, counter_path),
         {:ok, current_value} <- Jason.decode(data),
         {:ok, meta} <- ObjectStoreX.head(store, counter_path) do
      new_value = update_fn.(current_value)
      new_data = Jason.encode!(new_value)

      # Attempt CAS update
      case ObjectStoreX.put(store, counter_path, new_data,
             mode: {:update, %{etag: meta.etag, version: meta.version}}
           ) do
        {:ok, _result} ->
          {:ok, new_value}

        {:error, :precondition_failed} ->
          # Conflict - retry with backoff
          if attempt < max_retries - 1 do
            backoff_delay = calculate_backoff(attempt)
            Process.sleep(backoff_delay)
            do_update_with_retry(store, key, update_fn, attempt + 1, max_retries)
          else
            {:error, :max_retries_exceeded}
          end

        {:error, reason} ->
          {:error, reason}
      end
    else
      error -> error
    end
  end

  # Private helpers

  defp counter_path(key) do
    "counters/#{key}"
  end

  defp calculate_backoff(attempt) do
    # Exponential backoff with jitter: base_delay * 2^attempt + random jitter
    base_delay = 10
    max_delay = 1000
    delay = min(base_delay * :math.pow(2, attempt), max_delay)
    jitter = :rand.uniform(trunc(delay * 0.3))
    trunc(delay + jitter)
  end
end
