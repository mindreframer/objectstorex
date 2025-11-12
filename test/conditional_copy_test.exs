defmodule ObjectStoreX.ConditionalCopyTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, store} = ObjectStoreX.new(:memory)
    %{store: store}
  end

  # OBX003_4A_T1: Test copy_if_not_exists succeeds when destination empty
  test "OBX003_4A_T1: copy_if_not_exists succeeds when destination doesn't exist", %{
    store: store
  } do
    # Create source object
    :ok = ObjectStoreX.put(store, "source.txt", "source data")

    # Copy to non-existent destination
    result = ObjectStoreX.copy_if_not_exists(store, "source.txt", "destination.txt")

    assert :ok = result

    # Verify both source and destination exist
    {:ok, source_data} = ObjectStoreX.get(store, "source.txt")
    {:ok, dest_data} = ObjectStoreX.get(store, "destination.txt")
    assert source_data == "source data"
    assert dest_data == "source data"
  end

  # OBX003_4A_T2: Test copy_if_not_exists fails when destination exists
  test "OBX003_4A_T2: copy_if_not_exists fails when destination already exists", %{store: store} do
    # Create source and destination objects
    :ok = ObjectStoreX.put(store, "source.txt", "source data")
    :ok = ObjectStoreX.put(store, "destination.txt", "existing data")

    # Try to copy to existing destination
    result = ObjectStoreX.copy_if_not_exists(store, "source.txt", "destination.txt")

    assert {:error, :already_exists} = result

    # Verify destination data is unchanged
    {:ok, dest_data} = ObjectStoreX.get(store, "destination.txt")
    assert dest_data == "existing data"
  end

  # OBX003_4A_T3: Test copy_if_not_exists with Memory provider (atomic)
  test "OBX003_4A_T3: copy_if_not_exists is atomic with Memory provider", %{store: store} do
    # Create source object
    :ok = ObjectStoreX.put(store, "atomic-source.txt", "atomic test")

    # First copy should succeed
    result1 = ObjectStoreX.copy_if_not_exists(store, "atomic-source.txt", "atomic-dest.txt")
    assert :ok = result1

    # Second copy to same destination should fail atomically
    result2 = ObjectStoreX.copy_if_not_exists(store, "atomic-source.txt", "atomic-dest.txt")
    assert {:error, :already_exists} = result2

    # Verify destination has correct data from first copy
    {:ok, data} = ObjectStoreX.get(store, "atomic-dest.txt")
    assert data == "atomic test"
  end

  # OBX003_4A_T4: Test copy_if_not_exists with Local provider
  test "OBX003_4A_T4: copy_if_not_exists works with Local provider" do
    # Create a temporary directory for local storage
    tmp_dir = System.tmp_dir!() |> Path.join("objectstorex_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    try do
      {:ok, store} = ObjectStoreX.new(:local, path: tmp_dir)

      # Create source object
      :ok = ObjectStoreX.put(store, "local-source.txt", "local data")

      # Copy to non-existent destination
      result = ObjectStoreX.copy_if_not_exists(store, "local-source.txt", "local-dest.txt")
      assert :ok = result

      # Verify copy succeeded
      {:ok, data} = ObjectStoreX.get(store, "local-dest.txt")
      assert data == "local data"

      # Try to copy again, should fail
      result2 = ObjectStoreX.copy_if_not_exists(store, "local-source.txt", "local-dest.txt")
      assert {:error, :already_exists} = result2
    after
      # Cleanup
      File.rm_rf!(tmp_dir)
    end
  end

  # OBX003_4A_T5: Test rename_if_not_exists moves object
  test "OBX003_4A_T5: rename_if_not_exists moves object when destination doesn't exist", %{
    store: store
  } do
    # Create source object
    :ok = ObjectStoreX.put(store, "old-name.txt", "rename test")

    # Rename to non-existent destination
    result = ObjectStoreX.rename_if_not_exists(store, "old-name.txt", "new-name.txt")

    assert :ok = result

    # Verify source no longer exists
    result_source = ObjectStoreX.get(store, "old-name.txt")
    assert {:error, :not_found} = result_source

    # Verify destination exists with correct data
    {:ok, data} = ObjectStoreX.get(store, "new-name.txt")
    assert data == "rename test"
  end

  # OBX003_4A_T6: Test rename_if_not_exists fails if destination exists
  test "OBX003_4A_T6: rename_if_not_exists fails when destination already exists", %{
    store: store
  } do
    # Create source and destination objects
    :ok = ObjectStoreX.put(store, "old.txt", "source data")
    :ok = ObjectStoreX.put(store, "new.txt", "destination data")

    # Try to rename to existing destination
    result = ObjectStoreX.rename_if_not_exists(store, "old.txt", "new.txt")

    assert {:error, :already_exists} = result

    # Verify both objects still exist with original data
    {:ok, source_data} = ObjectStoreX.get(store, "old.txt")
    {:ok, dest_data} = ObjectStoreX.get(store, "new.txt")
    assert source_data == "source data"
    assert dest_data == "destination data"
  end

  # Additional test: copy_if_not_exists with non-existent source
  test "copy_if_not_exists returns error when source doesn't exist", %{store: store} do
    result = ObjectStoreX.copy_if_not_exists(store, "non-existent.txt", "destination.txt")

    assert {:error, :not_found} = result
  end

  # Additional test: rename_if_not_exists with non-existent source
  test "rename_if_not_exists returns error when source doesn't exist", %{store: store} do
    result = ObjectStoreX.rename_if_not_exists(store, "non-existent.txt", "destination.txt")

    assert {:error, :not_found} = result
  end
end
