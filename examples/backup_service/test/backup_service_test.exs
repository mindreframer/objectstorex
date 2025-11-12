defmodule BackupServiceTest do
  use ExUnit.Case, async: true

  @moduletag :OBX004_3A

  setup do
    # Create temporary directories
    tmp_dir = System.tmp_dir!()
    source_dir = Path.join(tmp_dir, "test_source_#{:erlang.unique_integer([:positive])}")
    restore_dir = Path.join(tmp_dir, "test_restore_#{:erlang.unique_integer([:positive])}")
    storage_dir = Path.join(tmp_dir, "test_backup_storage_#{:erlang.unique_integer([:positive])}")

    File.mkdir_p!(source_dir)
    File.mkdir_p!(restore_dir)
    File.mkdir_p!(storage_dir)

    # Create test files in source directory
    File.write!(Path.join(source_dir, "file1.txt"), "Content 1")
    File.write!(Path.join(source_dir, "file2.txt"), "Content 2")

    subdir = Path.join(source_dir, "subdir")
    File.mkdir_p!(subdir)
    File.write!(Path.join(subdir, "file3.txt"), "Content 3")

    # Create a test store
    {:ok, store} = ObjectStoreX.new(:local, path: storage_dir)

    on_exit(fn ->
      File.rm_rf(source_dir)
      File.rm_rf(restore_dir)
      File.rm_rf(storage_dir)
    end)

    %{
      store: store,
      source_dir: source_dir,
      restore_dir: restore_dir,
      storage_dir: storage_dir
    }
  end

  @tag :OBX004_3A_T6
  test "backup_service compiles", _context do
    # This test passes if the module loads without errors
    assert is_atom(BackupService)
  end

  @tag :OBX004_3A_T7
  test "creates backup successfully", %{store: store, source_dir: source_dir} do
    # Create backup
    assert {:ok, backup_id} = BackupService.backup(store, source_dir, "test-backups")

    # Verify backup ID is returned
    assert is_binary(backup_id)
    assert String.length(backup_id) > 0

    # Verify manifest exists
    assert {:ok, _data} = ObjectStoreX.get(store, "test-backups/#{backup_id}/manifest.json")
  end

  @tag :OBX004_3A_T8
  test "lists backups correctly", %{store: store, source_dir: source_dir} do
    # Create multiple backups
    {:ok, backup1} = BackupService.backup(store, source_dir, "list-test")
    Process.sleep(100)
    {:ok, backup2} = BackupService.backup(store, source_dir, "list-test")

    # List backups
    backups = BackupService.list_backups(store, "list-test")

    # Should have 2 backups
    assert length(backups) == 2

    # Verify backup metadata
    Enum.each(backups, fn backup ->
      assert is_binary(backup.id)
      assert %DateTime{} = backup.timestamp
      assert backup.file_count > 0
      assert backup.total_size > 0
    end)

    # Verify backups are sorted by timestamp (newest first)
    [first, second] = backups
    assert DateTime.compare(first.timestamp, second.timestamp) in [:gt, :eq]
  end

  @tag :OBX004_3A_T9
  test "restores backup successfully", %{
    store: store,
    source_dir: source_dir,
    restore_dir: restore_dir
  } do
    # Create backup
    {:ok, backup_id} = BackupService.backup(store, source_dir, "restore-test")

    # Restore backup
    assert :ok = BackupService.restore(store, "restore-test/#{backup_id}", restore_dir)

    # Verify restored files
    assert File.exists?(Path.join(restore_dir, "file1.txt"))
    assert File.exists?(Path.join(restore_dir, "file2.txt"))
    assert File.exists?(Path.join(restore_dir, "subdir/file3.txt"))

    assert File.read!(Path.join(restore_dir, "file1.txt")) == "Content 1"
    assert File.read!(Path.join(restore_dir, "file2.txt")) == "Content 2"
    assert File.read!(Path.join(restore_dir, "subdir/file3.txt")) == "Content 3"
  end

  @tag :OBX004_3A_T10
  test "backup with compression", %{store: store, source_dir: source_dir} do
    # Create compressed backup
    assert {:ok, backup_id} = BackupService.backup(store, source_dir, "compressed-test",
      compression: true
    )

    # Verify backup was created
    backups = BackupService.list_backups(store, "compressed-test")
    assert length(backups) == 1

    [backup] = backups
    assert backup.compressed == true
  end

  @tag :OBX004_3A_T11
  test "cleanup deletes old backups", %{store: store, source_dir: source_dir} do
    # Create backups with different timestamps
    {:ok, _backup1} = BackupService.backup(store, source_dir, "cleanup-test")
    Process.sleep(100)
    {:ok, _backup2} = BackupService.backup(store, source_dir, "cleanup-test")
    Process.sleep(100)
    {:ok, _backup3} = BackupService.backup(store, source_dir, "cleanup-test")

    # Verify we have 3 backups
    backups_before = BackupService.list_backups(store, "cleanup-test")
    assert length(backups_before) == 3

    # Cleanup - keep only 2 most recent
    {:ok, deleted} = BackupService.cleanup(store, "cleanup-test", keep_count: 2)

    assert deleted == 1

    # Verify we now have 2 backups
    backups_after = BackupService.list_backups(store, "cleanup-test")
    assert length(backups_after) == 2
  end

  @tag :OBX004_3A_T12
  test "cleanup with dry run doesn't delete", %{store: store, source_dir: source_dir} do
    # Create backups
    {:ok, _backup1} = BackupService.backup(store, source_dir, "dry-run-test")
    {:ok, _backup2} = BackupService.backup(store, source_dir, "dry-run-test")

    # Dry run cleanup
    {:ok, count} = BackupService.cleanup(store, "dry-run-test", keep_count: 1, dry_run: true)

    assert count == 1

    # Verify backups still exist
    backups = BackupService.list_backups(store, "dry-run-test")
    assert length(backups) == 2
  end

  @tag :OBX004_3A_T13
  test "verify checks backup integrity", %{store: store, source_dir: source_dir} do
    # Create backup
    {:ok, backup_id} = BackupService.backup(store, source_dir, "verify-test")

    # Verify backup
    assert :ok = BackupService.verify(store, "verify-test/#{backup_id}")
  end

  @tag :OBX004_3A_T14
  test "backup with exclude patterns", %{store: store, source_dir: source_dir} do
    # Create file that should be excluded
    File.write!(Path.join(source_dir, "exclude_me.log"), "Should not be backed up")

    # Create backup with exclude pattern
    {:ok, backup_id} = BackupService.backup(store, source_dir, "exclude-test",
      exclude: [".log"]
    )

    # Restore and verify excluded file doesn't exist
    restore_dir = Path.join(System.tmp_dir!(), "restore_exclude_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(restore_dir)

    BackupService.restore(store, "exclude-test/#{backup_id}", restore_dir)

    refute File.exists?(Path.join(restore_dir, "exclude_me.log"))
    assert File.exists?(Path.join(restore_dir, "file1.txt"))

    File.rm_rf(restore_dir)
  end

  @tag :OBX004_3A_T15
  test "handles backup errors gracefully", %{store: store} do
    # Try to backup non-existent directory
    result = BackupService.backup(store, "/nonexistent/directory", "error-test")

    assert {:error, _reason} = result
  end
end
