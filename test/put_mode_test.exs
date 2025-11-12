defmodule ObjectStoreX.PutModeTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, store} = ObjectStoreX.new(:memory)
    %{store: store}
  end

  # OBX003_1A_T1: Test put with mode :overwrite (default behavior)
  test "OBX003_1A_T1: put with mode :overwrite overwrites existing object", %{store: store} do
    # Create initial object
    :ok = ObjectStoreX.put(store, "test.txt", "initial")

    # Overwrite with mode :overwrite
    {:ok, meta} = ObjectStoreX.put(store, "test.txt", "updated", mode: :overwrite)

    assert is_map(meta)
    assert Map.has_key?(meta, :etag)
    assert Map.has_key?(meta, :version)

    # Verify data was updated
    {:ok, data} = ObjectStoreX.get(store, "test.txt")
    assert data == "updated"
  end

  # OBX003_1A_T2: Test put with mode :create succeeds if not exists
  test "OBX003_1A_T2: put with mode :create succeeds if object doesn't exist", %{store: store} do
    # Create with :create mode
    result = ObjectStoreX.put(store, "new.txt", "data", mode: :create)

    assert {:ok, meta} = result
    assert is_map(meta)
    assert Map.has_key?(meta, :etag)

    # Verify data was created
    {:ok, data} = ObjectStoreX.get(store, "new.txt")
    assert data == "data"
  end

  # OBX003_1A_T3: Test put with mode :create fails if exists (AlreadyExists)
  test "OBX003_1A_T3: put with mode :create fails if object already exists", %{store: store} do
    # Create initial object
    :ok = ObjectStoreX.put(store, "existing.txt", "initial")

    # Try to create again with :create mode
    result = ObjectStoreX.put(store, "existing.txt", "new data", mode: :create)

    assert {:error, :already_exists} = result

    # Verify original data is unchanged
    {:ok, data} = ObjectStoreX.get(store, "existing.txt")
    assert data == "initial"
  end

  # OBX003_1A_T4: Test put returns etag in result
  test "OBX003_1A_T4: put with mode returns etag and version in result", %{store: store} do
    {:ok, meta} = ObjectStoreX.put(store, "test.txt", "data", mode: :overwrite)

    assert is_map(meta)
    assert Map.has_key?(meta, :etag)
    assert Map.has_key?(meta, :version)
    assert is_binary(meta.etag) or is_nil(meta.etag)
    assert is_binary(meta.version) or is_nil(meta.version)
  end

  # OBX003_1A_T5: Test put with mode {:update, version} succeeds on match
  test "OBX003_1A_T5: put with mode {:update, version} succeeds when version matches", %{
    store: store
  } do
    # Create initial object with mode to get etag
    {:ok, initial_meta} = ObjectStoreX.put(store, "cas.txt", "v1", mode: :overwrite)

    # Get current metadata
    {:ok, current_meta} = ObjectStoreX.head(store, "cas.txt")

    # Update with matching etag
    etag = current_meta[:etag] || initial_meta.etag

    result =
      ObjectStoreX.put(store, "cas.txt", "v2", mode: {:update, %{etag: etag, version: nil}})

    assert {:ok, _meta} = result

    # Verify data was updated
    {:ok, data} = ObjectStoreX.get(store, "cas.txt")
    assert data == "v2"
  end

  # OBX003_1A_T6: Test put with mode {:update, version} fails on mismatch (Precondition)
  test "OBX003_1A_T6: put with mode {:update, version} fails when version doesn't match", %{
    store: store
  } do
    # Create initial object
    {:ok, _meta} = ObjectStoreX.put(store, "cas.txt", "v1", mode: :overwrite)

    # Try to update with wrong/stale etag
    result =
      ObjectStoreX.put(store, "cas.txt", "v2",
        mode: {:update, %{etag: "wrong-etag", version: nil}}
      )

    assert {:error, :precondition_failed} = result

    # Verify original data is unchanged
    {:ok, data} = ObjectStoreX.get(store, "cas.txt")
    assert data == "v1"
  end

  # OBX003_1A_T7: Test CAS operation with correct etag
  test "OBX003_1A_T7: CAS operation succeeds with correct etag", %{store: store} do
    # Create object
    {:ok, meta1} = ObjectStoreX.put(store, "counter.json", "1", mode: :overwrite)

    # Get current state
    {:ok, current_data} = ObjectStoreX.get(store, "counter.json")
    {:ok, current_meta} = ObjectStoreX.head(store, "counter.json")

    assert current_data == "1"

    # Perform CAS with correct etag
    etag = current_meta[:etag] || meta1.etag

    {:ok, _meta2} =
      ObjectStoreX.put(store, "counter.json", "2", mode: {:update, %{etag: etag, version: nil}})

    # Verify update succeeded
    {:ok, new_data} = ObjectStoreX.get(store, "counter.json")
    assert new_data == "2"
  end

  # OBX003_1A_T8: Test CAS operation with stale etag
  test "OBX003_1A_T8: CAS operation fails with stale etag", %{store: store} do
    # Create object and get etag
    {:ok, meta1} = ObjectStoreX.put(store, "counter.json", "1", mode: :overwrite)
    stale_etag = meta1.etag

    # Someone else updates the object
    {:ok, _meta2} = ObjectStoreX.put(store, "counter.json", "2", mode: :overwrite)

    # Try to update with stale etag
    result =
      ObjectStoreX.put(store, "counter.json", "3",
        mode: {:update, %{etag: stale_etag, version: nil}}
      )

    assert {:error, :precondition_failed} = result

    # Verify the second update is still in place
    {:ok, data} = ObjectStoreX.get(store, "counter.json")
    assert data == "2"
  end
end
