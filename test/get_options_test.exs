defmodule ObjectStoreX.GetOptionsTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, store} = ObjectStoreX.new(:memory)
    {:ok, store: store}
  end

  describe "OBX003_2A: GetOptions Infrastructure" do
    @tag :OBX003_2A_T1
    test "get with if_match returns data when etag matches", %{store: store} do
      # Put an object to get an etag
      test_data = "Hello, World!"
      {:ok, put_result} = ObjectStoreX.put(store, "test.txt", test_data, mode: :create)
      etag = put_result.etag

      # Get with matching etag
      {:ok, data, meta} = ObjectStoreX.get(store, "test.txt", if_match: etag)
      assert data == test_data
      assert is_map(meta)
      assert meta[:etag] == etag
    end

    @tag :OBX003_2A_T2
    test "get with if_match fails when etag differs", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      {:ok, _put_result} = ObjectStoreX.put(store, "test.txt", test_data, mode: :create)

      # Get with wrong etag
      result = ObjectStoreX.get(store, "test.txt", if_match: "wrong-etag-12345")

      assert result == {:error, :precondition_failed}
    end

    @tag :OBX003_2A_T3
    test "get with if_none_match returns :not_modified when matches", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      {:ok, put_result} = ObjectStoreX.put(store, "test.txt", test_data, mode: :create)
      etag = put_result.etag

      # Get with matching etag (should return not_modified)
      result = ObjectStoreX.get(store, "test.txt", if_none_match: etag)

      assert result == {:error, :not_modified}
    end

    @tag :OBX003_2A_T4
    test "get with if_none_match returns data when differs", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      {:ok, put_result} = ObjectStoreX.put(store, "test.txt", test_data, mode: :create)
      etag = put_result.etag

      # Get with different etag (should return data)
      {:ok, data, meta} = ObjectStoreX.get(store, "test.txt", if_none_match: "different-etag")
      assert data == test_data
      assert meta[:etag] == etag
    end

    @tag :OBX003_2A_T5
    test "get with if_modified_since", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      :ok = ObjectStoreX.put(store, "test.txt", test_data)

      # Request with if_modified_since set to 1 hour ago (should return data)
      past_time = DateTime.add(DateTime.utc_now(), -3600, :second)
      result = ObjectStoreX.get(store, "test.txt", if_modified_since: past_time)

      # Should return data since object is newer
      case result do
        {:ok, data, _meta} -> assert data == test_data
      end
    end

    @tag :OBX003_2A_T6
    test "get with if_unmodified_since", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      :ok = ObjectStoreX.put(store, "test.txt", test_data)

      # Request with if_unmodified_since set to 1 hour in the future
      future_time = DateTime.add(DateTime.utc_now(), 3600, :second)
      result = ObjectStoreX.get(store, "test.txt", if_unmodified_since: future_time)

      # Should return data since object hasn't been modified
      case result do
        {:ok, data, _meta} -> assert data == test_data
      end
    end

    @tag :OBX003_2A_T7
    test "get with range option", %{store: store} do
      # Put an object with some data
      test_data = "0123456789ABCDEFGHIJ"
      :ok = ObjectStoreX.put(store, "test.txt", test_data)

      # Get a range of bytes (first 10 bytes: 0-9)
      {:ok, data, _meta} = ObjectStoreX.get(store, "test.txt", range: {0, 10})
      assert data == "0123456789"
    end

    @tag :OBX003_2A_T8
    test "get with head: true returns metadata only", %{store: store} do
      # Put an object
      test_data = "Hello, World!"
      :ok = ObjectStoreX.put(store, "test.txt", test_data)

      # Get with head: true
      {:ok, data, meta} = ObjectStoreX.get(store, "test.txt", head: true)

      # Data should be empty for head-only request
      assert data == ""
      assert is_map(meta)
      assert meta[:size] == byte_size(test_data)
    end

    @tag :OBX003_2A_T9
    test "get with version returns specific version (provider-specific)", %{store: store} do
      # Note: Version support depends on the provider
      # Memory store may not support versioning
      test_data = "Hello, World!"
      {:ok, put_result} = ObjectStoreX.put(store, "test.txt", test_data, mode: :create)

      # Try to get with version (may not be supported by memory store)
      case put_result.version do
        "" ->
          # Version not supported by provider, skip this test
          :ok

        version when is_binary(version) ->
          # Try to get with version
          result = ObjectStoreX.get(store, "test.txt", version: version)

          case result do
            {:ok, data, _meta} -> assert data == test_data
            {:error, :not_supported} -> :ok
          end
      end
    end
  end

  describe "GetOptions and Range struct tests" do
    test "GetOptions.new/0 creates default struct" do
      opts = ObjectStoreX.GetOptions.new()
      assert %ObjectStoreX.GetOptions{} = opts
      assert opts.if_match == nil
      assert opts.if_none_match == nil
      assert opts.head == false
    end

    test "GetOptions.from_keyword/1 creates struct from keyword list" do
      opts =
        ObjectStoreX.GetOptions.from_keyword(
          if_match: "abc123",
          head: true
        )

      assert opts.if_match == "abc123"
      assert opts.head == true
    end

    test "Range.new/2 creates valid range" do
      range = ObjectStoreX.Range.new(0, 1000)
      assert %ObjectStoreX.Range{start: 0, end: 1000} = range
    end

    test "Range.size/1 calculates range size" do
      range = ObjectStoreX.Range.new(100, 200)
      assert ObjectStoreX.Range.size(range) == 100
    end
  end
end
