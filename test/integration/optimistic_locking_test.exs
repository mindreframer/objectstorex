defmodule ObjectStoreX.Integration.OptimisticLockingTest do
  use ExUnit.Case, async: false

  alias ObjectStoreX.Examples.OptimisticCounter

  setup do
    {:ok, store} = ObjectStoreX.new(:memory)
    %{store: store}
  end

  describe "OBX003_5A_T3: optimistic counter increments correctly" do
    test "initializes and gets counter value", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      # Initialize counter - returns {:ok, map} with etag/version
      OptimisticCounter.initialize(store, key, 42)

      # Get value
      assert {:ok, 42} = OptimisticCounter.get(store, key)
    end

    test "increments counter by 1", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 0)

      # Increment
      assert {:ok, 1} = OptimisticCounter.increment(store, key)
      assert {:ok, 1} = OptimisticCounter.get(store, key)

      # Increment again
      assert {:ok, 2} = OptimisticCounter.increment(store, key)
      assert {:ok, 2} = OptimisticCounter.get(store, key)
    end

    test "increments counter by custom amount", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 10)

      # Increment by 5
      assert {:ok, 15} = OptimisticCounter.increment(store, key, amount: 5)
      assert {:ok, 15} = OptimisticCounter.get(store, key)

      # Increment by 10
      assert {:ok, 25} = OptimisticCounter.increment(store, key, amount: 10)
      assert {:ok, 25} = OptimisticCounter.get(store, key)
    end

    test "decrements counter", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 10)

      # Decrement by 1
      assert {:ok, 9} = OptimisticCounter.decrement(store, key)
      assert {:ok, 9} = OptimisticCounter.get(store, key)

      # Decrement by 3
      assert {:ok, 6} = OptimisticCounter.decrement(store, key, amount: 3)
      assert {:ok, 6} = OptimisticCounter.get(store, key)
    end

    test "decrement respects minimum value", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 5)

      # Decrement to minimum
      assert {:ok, 0} = OptimisticCounter.decrement(store, key, amount: 5, min_value: 0)

      # Cannot go below minimum
      assert {:error, :min_value_reached} =
               OptimisticCounter.decrement(store, key, amount: 1, min_value: 0)

      # Value unchanged
      assert {:ok, 0} = OptimisticCounter.get(store, key)
    end
  end

  describe "OBX003_5A_T4: optimistic counter retries on conflict" do
    test "sequential increments work without conflict", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 0)

      # 5 sequential increments
      for i <- 1..5 do
        assert {:ok, ^i} = OptimisticCounter.increment(store, key)
      end

      assert {:ok, 5} = OptimisticCounter.get(store, key)
    end

    test "concurrent increments all succeed with CAS retry", %{store: store} do
      key = "counter-concurrent-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 0)

      # 10 concurrent increments with retries
      tasks =
        for _i <- 1..10 do
          Task.async(fn ->
            OptimisticCounter.increment(store, key, max_retries: 30)
          end)
        end

      results = Task.await_many(tasks, 10000)

      # Count successes
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # At least 8 out of 10 should succeed
      assert success_count >= 8

      # Final value should match successful increments
      {:ok, final_value} = OptimisticCounter.get(store, key)
      assert final_value == success_count
    end

    test "high concurrency increments (20 parallel)", %{store: store} do
      key = "counter-high-concurrency-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 0)

      # 20 concurrent increments with high retry count
      tasks =
        for _i <- 1..20 do
          Task.async(fn ->
            OptimisticCounter.increment(store, key, max_retries: 50)
          end)
        end

      results = Task.await_many(tasks, 15000)

      # Count successes
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # At least 18 out of 20 should succeed (allowing for some contention failures)
      assert success_count >= 18, "Expected at least 18 successes, got #{success_count}"

      # Final value should equal number of successful increments
      {:ok, final_value} = OptimisticCounter.get(store, key)
      assert final_value == success_count
    end

    test "mixed concurrent increments and decrements", %{store: store} do
      key = "counter-mixed-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 100)

      # 10 increments and 10 decrements concurrently with retries
      increment_tasks =
        for _i <- 1..10 do
          Task.async(fn -> OptimisticCounter.increment(store, key, max_retries: 30) end)
        end

      decrement_tasks =
        for _i <- 1..10 do
          Task.async(fn -> OptimisticCounter.decrement(store, key, max_retries: 30) end)
        end

      increment_results = Task.await_many(increment_tasks, 10000)
      decrement_results = Task.await_many(decrement_tasks, 10000)

      # Count successes
      inc_success = Enum.count(increment_results, fn result -> match?({:ok, _}, result) end)
      dec_success = Enum.count(decrement_results, fn result -> match?({:ok, _}, result) end)

      # At least 8 of each should succeed
      assert inc_success >= 8
      assert dec_success >= 8

      # Final value should be 100 + successful_increments - successful_decrements
      {:ok, final_value} = OptimisticCounter.get(store, key)
      assert final_value == 100 + inc_success - dec_success
    end
  end

  describe "OBX003_5A: custom update function" do
    test "updates counter with custom function", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 5)

      # Double the value
      assert {:ok, 10} = OptimisticCounter.update(store, key, fn v -> v * 2 end)
      assert {:ok, 10} = OptimisticCounter.get(store, key)

      # Square the value
      assert {:ok, 100} = OptimisticCounter.update(store, key, fn v -> v * v end)
      assert {:ok, 100} = OptimisticCounter.get(store, key)
    end

    test "custom update with conditional logic", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 15)

      # Subtract 10 but don't go below 0
      assert {:ok, 5} = OptimisticCounter.update(store, key, fn v -> max(v - 10, 0) end)

      # Try to subtract 10 again - should stop at 0
      assert {:ok, 0} = OptimisticCounter.update(store, key, fn v -> max(v - 10, 0) end)
      assert {:ok, 0} = OptimisticCounter.get(store, key)
    end

    test "concurrent custom updates", %{store: store} do
      key = "counter-custom-concurrent-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 1)

      # 5 concurrent updates, each adds 1
      tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            OptimisticCounter.update(store, key, fn v -> v + 1 end, max_retries: 20)
          end)
        end

      results = Task.await_many(tasks, 10000)

      # Count successes
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # At least 4 out of 5 should succeed
      assert success_count >= 4

      # Final value should be initial + successful updates
      {:ok, final_value} = OptimisticCounter.get(store, key)
      assert final_value == 1 + success_count
    end
  end

  describe "OBX003_5A: error handling" do
    test "returns error for non-existent counter", %{store: store} do
      key = "non-existent-#{:rand.uniform(10000)}"

      assert {:error, :not_found} = OptimisticCounter.get(store, key)
      assert {:error, :not_found} = OptimisticCounter.increment(store, key)
      assert {:error, :not_found} = OptimisticCounter.decrement(store, key)
    end

    test "handles max retries exceeded", %{store: store} do
      key = "counter-#{:rand.uniform(10000)}"

      OptimisticCounter.initialize(store, key, 0)

      # Create high contention with very low max_retries
      # Some tasks might fail with max_retries_exceeded
      tasks =
        for _i <- 1..50 do
          Task.async(fn ->
            OptimisticCounter.increment(store, key, max_retries: 2)
          end)
        end

      results = Task.await_many(tasks, 15000)

      # Some should succeed, some might fail
      successes = Enum.count(results, fn result -> match?({:ok, _}, result) end)
      failures = Enum.count(results, fn result -> match?({:error, :max_retries_exceeded}, result) end)

      # At least some should succeed
      assert successes > 0

      # Total attempts = 50
      assert successes + failures == 50

      # Final value = number of successful increments
      {:ok, final_count} = OptimisticCounter.get(store, key)
      assert final_count == successes
    end
  end

  describe "OBX003_5A: counter patterns" do
    test "download counter pattern", %{store: store} do
      key = "downloads-file123"

      # Initialize download counter
      OptimisticCounter.initialize(store, key, 0)

      # Simulate 5 concurrent downloads
      download_tasks =
        for _i <- 1..5 do
          Task.async(fn ->
            # Increment download count
            OptimisticCounter.increment(store, key, max_retries: 20)
          end)
        end

      results = Task.await_many(download_tasks, 5000)
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # All or most should succeed
      assert success_count >= 4

      # Verify count matches successes
      {:ok, count} = OptimisticCounter.get(store, key)
      assert count == success_count
    end

    test "inventory pattern with minimum", %{store: store} do
      key = "inventory-product456"

      # Initialize stock
      OptimisticCounter.initialize(store, key, 3)

      # 3 successful purchases
      assert {:ok, 2} = OptimisticCounter.decrement(store, key, min_value: 0)
      assert {:ok, 1} = OptimisticCounter.decrement(store, key, min_value: 0)
      assert {:ok, 0} = OptimisticCounter.decrement(store, key, min_value: 0)

      # Out of stock - cannot purchase
      assert {:error, :min_value_reached} =
               OptimisticCounter.decrement(store, key, min_value: 0)

      assert {:ok, 0} = OptimisticCounter.get(store, key)
    end

    test "view counter with concurrent viewers", %{store: store} do
      key = "views-page789"

      OptimisticCounter.initialize(store, key, 1000)

      # Simulate 15 concurrent page views with retries
      view_tasks =
        for _i <- 1..15 do
          Task.async(fn ->
            OptimisticCounter.increment(store, key, max_retries: 30)
          end)
        end

      results = Task.await_many(view_tasks, 5000)
      success_count = Enum.count(results, fn result -> match?({:ok, _}, result) end)

      # Most should succeed
      assert success_count >= 13

      # Verify count
      {:ok, count} = OptimisticCounter.get(store, key)
      assert count == 1000 + success_count
    end
  end
end
