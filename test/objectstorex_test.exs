defmodule ObjectStoreXTest do
  use ExUnit.Case
  doctest ObjectStoreX

  describe "OBX001_1A: Infrastructure Tests" do
    test "OBX001_1A_T1: NIF loads successfully" do
      # Test that the NIF module is loaded
      assert Code.ensure_loaded?(ObjectStoreX.Native)
    end

    test "OBX001_1A_T2: Memory store creation (Tokio runtime initializes)" do
      # Creating a memory store tests that the Tokio runtime is initialized
      assert {:ok, store} = ObjectStoreX.new(:memory)
      assert is_reference(store)
    end

    test "OBX001_1A_T3: StoreWrapper resource creation" do
      # Test that the StoreWrapper resource is properly created
      {:ok, store} = ObjectStoreX.new(:memory)
      assert is_reference(store)
      # Verify we can use the resource
      assert :ok = ObjectStoreX.put(store, "test.txt", "data")
    end

    test "OBX001_1A_T4: Error atoms defined correctly" do
      # Test that error atoms work by triggering a not_found error
      {:ok, store} = ObjectStoreX.new(:memory)
      assert {:error, :not_found} = ObjectStoreX.get(store, "nonexistent.txt")
    end
  end

  describe "OBX001_2A: Memory Provider Basic Operations" do
    setup do
      {:ok, store} = ObjectStoreX.new(:memory)
      {:ok, store: store}
    end

    test "put and get roundtrip", %{store: store} do
      data = "Hello, World!"
      assert :ok = ObjectStoreX.put(store, "test.txt", data)
      assert {:ok, ^data} = ObjectStoreX.get(store, "test.txt")
    end

    test "get returns not_found for missing object", %{store: store} do
      assert {:error, :not_found} = ObjectStoreX.get(store, "missing.txt")
    end

    test "delete removes object", %{store: store} do
      data = "temporary"
      assert :ok = ObjectStoreX.put(store, "temp.txt", data)
      assert {:ok, ^data} = ObjectStoreX.get(store, "temp.txt")
      assert :ok = ObjectStoreX.delete(store, "temp.txt")
      assert {:error, :not_found} = ObjectStoreX.get(store, "temp.txt")
    end

    test "head returns metadata", %{store: store} do
      data = "Hello, World!"
      assert :ok = ObjectStoreX.put(store, "meta.txt", data)
      assert {:ok, meta} = ObjectStoreX.head(store, "meta.txt")
      assert is_map(meta)
      assert meta[:location] == "meta.txt"
      assert meta[:size] == byte_size(data)
      assert is_binary(meta[:last_modified])
    end

    test "head returns not_found for missing object", %{store: store} do
      assert {:error, :not_found} = ObjectStoreX.head(store, "missing.txt")
    end

    test "copy duplicates object", %{store: store} do
      data = "original"
      assert :ok = ObjectStoreX.put(store, "original.txt", data)
      assert :ok = ObjectStoreX.copy(store, "original.txt", "copy.txt")
      assert {:ok, ^data} = ObjectStoreX.get(store, "original.txt")
      assert {:ok, ^data} = ObjectStoreX.get(store, "copy.txt")
    end

    test "rename moves object", %{store: store} do
      data = "moving"
      assert :ok = ObjectStoreX.put(store, "old.txt", data)
      assert :ok = ObjectStoreX.rename(store, "old.txt", "new.txt")
      assert {:error, :not_found} = ObjectStoreX.get(store, "old.txt")
      assert {:ok, ^data} = ObjectStoreX.get(store, "new.txt")
    end

    test "binary data integrity", %{store: store} do
      # Test with binary data (not just strings)
      data = <<0, 1, 2, 3, 255, 254, 253>>
      assert :ok = ObjectStoreX.put(store, "binary.dat", data)
      assert {:ok, ^data} = ObjectStoreX.get(store, "binary.dat")
    end
  end

  describe "OBX001_4A: Local Provider Tests" do
    setup do
      # Create a temporary directory for local storage tests
      tmp_dir = System.tmp_dir!() |> Path.join("objectstorex_test_#{:rand.uniform(1_000_000)}")
      File.mkdir_p!(tmp_dir)
      {:ok, store} = ObjectStoreX.new(:local, path: tmp_dir)

      on_exit(fn ->
        File.rm_rf!(tmp_dir)
      end)

      {:ok, store: store, tmp_dir: tmp_dir}
    end

    test "OBX001_4A_T1: local filesystem store creation", %{store: store} do
      assert is_reference(store)
    end

    test "OBX001_4A_T2: local put creates file on disk", %{store: store, tmp_dir: tmp_dir} do
      data = "disk data"
      assert :ok = ObjectStoreX.put(store, "disk.txt", data)

      # Verify file exists on disk
      file_path = Path.join(tmp_dir, "disk.txt")
      assert File.exists?(file_path)
      assert File.read!(file_path) == data
    end

    test "OBX001_4A_T3: local get reads file from disk", %{store: store} do
      data = "filesystem"
      assert :ok = ObjectStoreX.put(store, "read.txt", data)
      assert {:ok, ^data} = ObjectStoreX.get(store, "read.txt")
    end

    test "OBX001_4A_T4: local delete removes file", %{store: store, tmp_dir: tmp_dir} do
      data = "temp"
      assert :ok = ObjectStoreX.put(store, "temp.txt", data)
      file_path = Path.join(tmp_dir, "temp.txt")
      assert File.exists?(file_path)

      assert :ok = ObjectStoreX.delete(store, "temp.txt")
      refute File.exists?(file_path)
    end
  end
end
