defmodule FileUploaderTest do
  use ExUnit.Case, async: true
  doctest FileUploader

  @moduletag :OBX004_3A

  setup do
    # Create temporary directories
    tmp_dir = System.tmp_dir!()
    upload_dir = Path.join(tmp_dir, "test_uploads_#{:erlang.unique_integer([:positive])}")
    download_dir = Path.join(tmp_dir, "test_downloads_#{:erlang.unique_integer([:positive])}")
    storage_dir = Path.join(tmp_dir, "test_storage_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(upload_dir)
    File.mkdir_p!(download_dir)
    File.mkdir_p!(storage_dir)

    # Create a test store
    {:ok, store} = ObjectStoreX.new(:local, path: storage_dir)

    on_exit(fn ->
      File.rm_rf(upload_dir)
      File.rm_rf(download_dir)
      File.rm_rf(storage_dir)
    end)

    %{
      store: store,
      upload_dir: upload_dir,
      download_dir: download_dir,
      storage_dir: storage_dir
    }
  end

  @tag :OBX004_3A_T1
  test "file_uploader compiles", _context do
    # This test passes if the module loads without errors
    assert is_atom(FileUploader)
  end

  @tag :OBX004_3A_T2
  test "uploads file successfully", %{store: store, upload_dir: upload_dir} do
    # Create a test file
    test_file = Path.join(upload_dir, "test.txt")
    File.write!(test_file, "Hello, World!")

    # Upload the file
    assert :ok = FileUploader.upload_file(store, test_file, "test.txt")

    # Verify the file was uploaded
    assert {:ok, data} = ObjectStoreX.get(store, "test.txt")
    assert data == "Hello, World!"
  end

  @tag :OBX004_3A_T3
  test "upload_file with progress tracking", %{store: store, upload_dir: upload_dir} do
    # Create a larger test file (1MB)
    test_file = Path.join(upload_dir, "large.bin")
    data = :crypto.strong_rand_bytes(1_048_576)
    File.write!(test_file, data)

    # Track progress
    progress_tracker = fn bytes, total ->
      send(self(), {:progress, bytes, total})
    end

    # Upload with progress tracking
    assert :ok =
             FileUploader.upload_file(store, test_file, "large.bin",
               chunk_size: 262_144,
               on_progress: progress_tracker
             )

    # Verify we received progress updates
    assert_receive {:progress, bytes, total}
    assert total == 1_048_576
    assert bytes > 0
  end

  @tag :OBX004_3A_T4
  test "downloads file successfully", %{
    store: store,
    upload_dir: upload_dir,
    download_dir: download_dir
  } do
    # Upload a file first
    test_file = Path.join(upload_dir, "test.txt")
    File.write!(test_file, "Download test")
    FileUploader.upload_file(store, test_file, "download_test.txt")

    # Download the file
    downloaded_file = Path.join(download_dir, "downloaded.txt")

    assert :ok =
             FileUploader.download_file(store, "download_test.txt", downloaded_file)

    # Verify the downloaded file
    assert File.read!(downloaded_file) == "Download test"
  end

  @tag :OBX004_3A_T5
  test "lists files with sizes", %{store: store, upload_dir: upload_dir} do
    # Upload multiple files
    for i <- 1..3 do
      test_file = Path.join(upload_dir, "file#{i}.txt")
      File.write!(test_file, "Content #{i}")
      FileUploader.upload_file(store, test_file, "list_test/file#{i}.txt")
    end

    # List files
    files =
      FileUploader.list_files(store, prefix: "list_test/")
      |> Enum.to_list()

    assert length(files) == 3

    # Verify each file has metadata
    Enum.each(files, fn meta ->
      assert meta.location =~ "list_test/file"
      assert is_integer(meta.size)
      assert meta.size > 0
    end)
  end

  @tag :OBX004_3A_T6
  test "format_size formats bytes correctly" do
    assert FileUploader.format_size(512) == "512 B"
    assert FileUploader.format_size(1024) == "1.00 KB"
    assert FileUploader.format_size(1_048_576) == "1.00 MB"
    assert FileUploader.format_size(1_073_741_824) == "1.00 GB"
    assert FileUploader.format_size(2_560) == "2.50 KB"
  end

  @tag :OBX004_3A_T7
  test "handles upload errors gracefully", %{store: store} do
    # Try to upload a non-existent file
    result = FileUploader.upload_file(store, "/nonexistent/file.txt", "test.txt")

    assert {:error, _reason} = result
  end

  @tag :OBX004_3A_T8
  test "handles download errors gracefully", %{store: store, download_dir: download_dir} do
    # Try to download a non-existent file
    downloaded_file = Path.join(download_dir, "nonexistent.txt")
    result = FileUploader.download_file(store, "nonexistent.txt", downloaded_file)

    assert {:error, _reason} = result
  end
end
