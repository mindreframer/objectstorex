# Error Handling Guide

This guide covers error handling patterns and retry strategies for ObjectStoreX.

## Table of Contents

- [Error Types](#error-types)
- [Error Handling Patterns](#error-handling-patterns)
- [Retry Strategies](#retry-strategies)
- [Retryable Errors](#retryable-errors)
- [Error Context](#error-context)
- [Production Patterns](#production-patterns)
- [Testing Error Handling](#testing-error-handling)

## Error Types

All ObjectStoreX operations return tagged tuples:

```elixir
{:ok, result}  # Success
{:error, reason}  # Failure
```

### Common Error Reasons

```elixir
:not_found            # Object doesn't exist
:already_exists       # Object already exists (create-only mode)
:precondition_failed  # Conditional operation failed (ETag mismatch)
:not_modified         # Object not modified (conditional GET)
:permission_denied    # Insufficient permissions
:not_supported        # Operation not supported by provider
:timeout              # Operation timed out
:network_error        # Network/connection error
:invalid_input        # Invalid parameters
{:unknown, message}   # Unknown error with details
```

### Error Examples

```elixir
# Object not found
{:error, :not_found} = ObjectStoreX.get(store, "missing.txt")

# Permission denied
{:error, :permission_denied} = ObjectStoreX.put(store, "protected/file.txt", "data")

# Already exists (create-only mode)
{:error, :already_exists} = ObjectStoreX.put(store, "exists.txt", "data", mode: :create)

# Precondition failed (CAS)
{:error, :precondition_failed} = ObjectStoreX.put(store, "file.txt", "data",
  mode: {:update, %{etag: "old-etag"}})

# Not modified (cached)
{:error, :not_modified} = ObjectStoreX.get(store, "file.txt",
  if_none_match: current_etag)
```

## Error Handling Patterns

### Basic Pattern Matching

```elixir
case ObjectStoreX.get(store, "file.txt") do
  {:ok, data} ->
    process(data)

  {:error, :not_found} ->
    Logger.warning("File not found")
    :not_found

  {:error, :permission_denied} ->
    Logger.error("Permission denied")
    :unauthorized

  {:error, :timeout} ->
    Logger.warning("Timeout, will retry")
    :retry

  {:error, reason} ->
    Logger.error("Unexpected error: #{inspect(reason)}")
    :error
end
```

### With Guards

```elixir
defmodule FileHandler do
  def get(store, path) do
    case ObjectStoreX.get(store, path) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} when reason in [:timeout, :network_error] ->
        # Retryable errors
        {:retry, reason}

      {:error, reason} when reason in [:not_found, :permission_denied] ->
        # Non-retryable errors
        {:error, reason}

      {:error, reason} ->
        {:error, {:unknown, reason}}
    end
  end
end
```

### Using Error Module

```elixir
alias ObjectStoreX.Error

case ObjectStoreX.get(store, "file.txt") do
  {:ok, data} ->
    {:ok, data}

  {:error, reason} ->
    Logger.error("Error: #{Error.format_error(reason)}")

    if Error.retryable?(reason) do
      {:retry, reason}
    else
      {:error, reason}
    end
end
```

## Retry Strategies

### Simple Retry

```elixir
defmodule SimpleRetry do
  def get_with_retry(store, path, retries \\ 3) do
    case ObjectStoreX.get(store, path) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} when retries > 0 ->
        if ObjectStoreX.Error.retryable?(reason) do
          :timer.sleep(1000)  # Wait 1 second
          get_with_retry(store, path, retries - 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
```

### Exponential Backoff

```elixir
defmodule ExponentialBackoff do
  def get_with_backoff(store, path, max_attempts \\ 5) do
    retry_with_backoff(fn ->
      ObjectStoreX.get(store, path)
    end, max_attempts)
  end

  defp retry_with_backoff(func, max_attempts, attempt \\ 1) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < max_attempts ->
        if ObjectStoreX.Error.retryable?(reason) do
          delay = calculate_backoff(attempt)
          Logger.info("Retrying in #{delay}ms (attempt #{attempt}/#{max_attempts})")
          :timer.sleep(delay)
          retry_with_backoff(func, max_attempts, attempt + 1)
        else
          {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp calculate_backoff(attempt) do
    base_delay = 100  # 100ms
    max_delay = 10_000  # 10 seconds
    # 100ms, 200ms, 400ms, 800ms, 1600ms, ...
    delay = base_delay * :math.pow(2, attempt - 1)
    min(trunc(delay), max_delay)
  end
end
```

### Jittered Backoff

```elixir
defmodule JitteredBackoff do
  defp calculate_backoff_with_jitter(attempt) do
    base_delay = 100
    max_delay = 10_000
    exponential_delay = base_delay * :math.pow(2, attempt - 1)
    max_backoff = min(trunc(exponential_delay), max_delay)

    # Add random jitter (0-50% of delay)
    jitter = :rand.uniform(trunc(max_backoff * 0.5))
    max_backoff + jitter
  end
end
```

### Circuit Breaker

```elixir
defmodule CircuitBreaker do
  use GenServer

  @failure_threshold 5
  @reset_timeout 60_000  # 1 minute

  def start_link(_) do
    GenServer.start_link(__MODULE__, :closed, name: __MODULE__)
  end

  def call(func) do
    case GenServer.call(__MODULE__, :check_state) do
      :open ->
        {:error, :circuit_open}

      :closed ->
        case func.() do
          {:ok, result} ->
            GenServer.cast(__MODULE__, :success)
            {:ok, result}

          {:error, reason} ->
            GenServer.cast(__MODULE__, :failure)
            {:error, reason}
        end
    end
  end

  def init(state) do
    {:ok, %{state: state, failures: 0}}
  end

  def handle_call(:check_state, _from, state) do
    {:reply, state.state, state}
  end

  def handle_cast(:success, state) do
    {:noreply, %{state | state: :closed, failures: 0}}
  end

  def handle_cast(:failure, state) do
    failures = state.failures + 1

    if failures >= @failure_threshold do
      Process.send_after(self(), :attempt_reset, @reset_timeout)
      {:noreply, %{state | state: :open, failures: failures}}
    else
      {:noreply, %{state | failures: failures}}
    end
  end

  def handle_info(:attempt_reset, state) do
    {:noreply, %{state | state: :closed, failures: 0}}
  end
end

# Usage
CircuitBreaker.call(fn ->
  ObjectStoreX.get(store, "file.txt")
end)
```

## Retryable Errors

Use `ObjectStoreX.Error.retryable?/1` to check if an error should be retried.

### Retryable

- `:timeout` - Operation may succeed on retry
- `:network_error` - Network may recover
- `:precondition_failed` - For CAS retry with new ETag

### Non-Retryable

- `:not_found` - Object doesn't exist
- `:already_exists` - Object exists
- `:permission_denied` - Credentials issue
- `:not_supported` - Feature not supported
- `:invalid_input` - Bad parameters
- `:not_modified` - Cache is valid (not an error)

### Example

```elixir
defmodule SmartRetry do
  def execute_with_retry(func, max_attempts \\ 3) do
    execute(func, max_attempts, 1)
  end

  defp execute(func, max_attempts, attempt) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < max_attempts ->
        if ObjectStoreX.Error.retryable?(reason) do
          delay = calculate_backoff(attempt)
          :timer.sleep(delay)
          execute(func, max_attempts, attempt + 1)
        else
          Logger.error("Non-retryable error: #{ObjectStoreX.Error.format_error(reason)}")
          {:error, reason}
        end

      {:error, reason} ->
        Logger.error("Max retries exceeded: #{ObjectStoreX.Error.format_error(reason)}")
        {:error, reason}
    end
  end

  defp calculate_backoff(attempt), do: min(100 * :math.pow(2, attempt), 10_000)
end
```

## Error Context

Errors can include detailed context information.

### Creating Errors with Context

```elixir
alias ObjectStoreX.Error

# Create detailed error
error = Error.with_context(:permission_denied, %{
  operation: :put,
  path: "protected/file.txt",
  provider: :s3,
  message: "Access Denied"
})

# => {:permission_denied, %{operation: :put, path: "protected/file.txt", ...}}
```

### Handling Detailed Errors

```elixir
case ObjectStoreX.get(store, "file.txt") do
  {:ok, data} ->
    {:ok, data}

  {:error, {reason, context}} when is_map(context) ->
    Logger.error("""
    Error: #{Error.format_error(reason)}
    Operation: #{context[:operation]}
    Path: #{context[:path]}
    Provider: #{context[:provider]}
    Message: #{context[:message]}
    """)
    {:error, reason}

  {:error, reason} ->
    Logger.error("Error: #{Error.format_error(reason)}")
    {:error, reason}
end
```

## Production Patterns

### Comprehensive Error Handler

```elixir
defmodule ObjectStore.SafeOps do
  require Logger
  alias ObjectStoreX.Error

  @max_retries 3
  @retry_delay 1000

  def safe_get(store, path, opts \\ []) do
    execute_with_retry(fn ->
      ObjectStoreX.get(store, path, opts)
    end)
  end

  def safe_put(store, path, data, opts \\ []) do
    execute_with_retry(fn ->
      ObjectStoreX.put(store, path, data, opts)
    end)
  end

  defp execute_with_retry(func) do
    execute_with_retry(func, @max_retries, 1)
  end

  defp execute_with_retry(func, max_retries, attempt) do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      :ok ->
        :ok

      {:error, reason} when attempt <= max_retries ->
        handle_error(func, reason, max_retries, attempt)

      {:error, reason} ->
        Logger.error("Operation failed after #{@max_retries} attempts: #{Error.format_error(reason)}")
        {:error, reason}
    end
  end

  defp handle_error(func, reason, max_retries, attempt) do
    if Error.retryable?(reason) do
      delay = calculate_backoff(attempt)
      Logger.warning("Retrying after #{delay}ms (attempt #{attempt}/#{max_retries}): #{Error.format_error(reason)}")
      :timer.sleep(delay)
      execute_with_retry(func, max_retries, attempt + 1)
    else
      Logger.error("Non-retryable error: #{Error.format_error(reason)}")
      {:error, reason}
    end
  end

  defp calculate_backoff(attempt) do
    base = @retry_delay
    max_delay = 30_000
    exponential = base * :math.pow(2, attempt - 1)
    jitter = :rand.uniform(trunc(exponential * 0.3))
    min(trunc(exponential) + jitter, max_delay)
  end
end
```

### Telemetry Integration

```elixir
defmodule ObjectStore.Telemetry do
  def execute_with_telemetry(operation, metadata, func) do
    start_time = System.monotonic_time()

    result = func.()

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:objectstorex, operation],
      %{duration: duration},
      Map.merge(metadata, %{result: result})
    )

    result
  end
end

# Usage
ObjectStore.Telemetry.execute_with_telemetry(
  :get,
  %{path: "file.txt"},
  fn -> ObjectStoreX.get(store, "file.txt") end
)
```

### Fallback Pattern

```elixir
defmodule ObjectStore.Fallback do
  def get_with_fallback(primary_store, fallback_store, path) do
    case ObjectStoreX.get(primary_store, path) do
      {:ok, data} ->
        {:ok, data}

      {:error, reason} ->
        Logger.warning("Primary store failed (#{inspect(reason)}), trying fallback")

        case ObjectStoreX.get(fallback_store, path) do
          {:ok, data} ->
            # Optionally sync back to primary
            spawn(fn ->
              ObjectStoreX.put(primary_store, path, data)
            end)
            {:ok, data}

          {:error, fallback_reason} ->
            Logger.error("Both stores failed: primary=#{inspect(reason)}, fallback=#{inspect(fallback_reason)}")
            {:error, reason}
        end
    end
  end
end
```

## Testing Error Handling

### Mock Errors

```elixir
defmodule ObjectStore.Mock do
  def get(_store, "timeout.txt"), do: {:error, :timeout}
  def get(_store, "not_found.txt"), do: {:error, :not_found}
  def get(_store, "permission_denied.txt"), do: {:error, :permission_denied}
  def get(store, path), do: ObjectStoreX.get(store, path)
end

# In tests
test "handles timeout error" do
  result = ObjectStore.SafeOps.safe_get(store, "timeout.txt")
  assert {:error, :timeout} = result
end
```

### Test Retry Logic

```elixir
defmodule RetryTest do
  use ExUnit.Case

  test "retries on timeout" do
    # Create agent to track attempts
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      count = Agent.get_and_update(agent, fn count -> {count + 1, count + 1} end)

      if count < 3 do
        {:error, :timeout}
      else
        {:ok, "success"}
      end
    end

    assert {:ok, "success"} = SmartRetry.execute_with_retry(func, 5)
    assert Agent.get(agent, & &1) == 3
  end

  test "does not retry non-retryable errors" do
    {:ok, agent} = Agent.start_link(fn -> 0 end)

    func = fn ->
      Agent.update(agent, &(&1 + 1))
      {:error, :not_found}
    end

    assert {:error, :not_found} = SmartRetry.execute_with_retry(func, 5)
    assert Agent.get(agent, & &1) == 1  # Only called once
  end
end
```

### Integration Tests

```elixir
defmodule IntegrationTest do
  use ExUnit.Case

  @tag :integration
  test "handles real S3 errors" do
    {:ok, store} = ObjectStoreX.new(:s3, bucket: "test-bucket", region: "us-east-1")

    # Test not_found
    assert {:error, :not_found} = ObjectStoreX.get(store, "missing-file.txt")

    # Test permission_denied (if configured)
    # assert {:error, :permission_denied} = ObjectStoreX.get(store, "protected/file.txt")
  end
end
```

## Error Logging Best Practices

### Structured Logging

```elixir
defmodule ObjectStore.Logger do
  require Logger

  def log_error(operation, path, error) do
    Logger.error("ObjectStore operation failed",
      operation: operation,
      path: path,
      error: ObjectStoreX.Error.format_error(error),
      error_atom: extract_error_atom(error),
      retryable: ObjectStoreX.Error.retryable?(error)
    )
  end

  defp extract_error_atom({atom, _context}), do: atom
  defp extract_error_atom(atom) when is_atom(atom), do: atom
  defp extract_error_atom(_), do: :unknown
end
```

### Metrics

```elixir
defmodule ObjectStore.Metrics do
  def record_error(operation, error) do
    error_type = extract_error_type(error)

    :telemetry.execute(
      [:objectstorex, :error],
      %{count: 1},
      %{operation: operation, error_type: error_type}
    )
  end

  defp extract_error_type({atom, _}), do: atom
  defp extract_error_type(atom) when is_atom(atom), do: atom
  defp extract_error_type(_), do: :unknown
end
```

## Next Steps

- [Getting Started Guide](getting_started.md)
- [Configuration Guide](configuration.md)
- [Streaming Guide](streaming.md)
- [Distributed Systems Guide](distributed_systems.md)
- [ObjectStoreX.Error Module](../lib/objectstorex/error.ex)
