# Backup Service Example

This example demonstrates how to use ObjectStoreX to build an automated backup service with retention policies.

## Features

- **Full and incremental backups**: Track file changes and backup only modified files
- **Retention policies**: Automatically delete old backups based on age or count
- **Compression**: Optional gzip compression to save storage space
- **Parallel uploads**: Upload multiple files concurrently for faster backups
- **Restore capability**: Restore backups to any location
- **Verification**: Verify backup integrity

## How It Works

The backup service creates timestamped backups with the following structure:

```
<prefix>/<timestamp>/
  manifest.json          # Backup metadata
  files/
    path/to/file1.txt
    path/to/file2.bin.gz
```

Each backup includes:
- **Manifest**: Metadata about the backup (timestamp, file count, size, etc.)
- **Files**: All backed up files, optionally compressed

## Installation

```bash
cd examples/backup_service
mix deps.get
```

## Usage

### Basic Backup

```elixir
# Create a backup store
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-backups",
  region: "us-east-1"
)

# Perform a full backup
{:ok, backup_id} = BackupService.backup(store, "/data", "app-backups")

IO.puts("Backup created: #{backup_id}")
```

### Backup with Options

```elixir
# Compressed, parallel backup
{:ok, backup_id} = BackupService.backup(store, "/data", "app-backups",
  compression: true,     # Enable gzip compression
  parallel: 4,           # Upload 4 files concurrently
  exclude: [".git", "node_modules", "*.log"]  # Exclude patterns
)
```

### Incremental Backup

```elixir
# First backup (full)
{:ok, backup1} = BackupService.backup(store, "/data", "incremental")

# ... time passes, files change ...

# Incremental backup (only changed files since backup1)
{:ok, backup2} = BackupService.backup(store, "/data", "incremental",
  incremental: true,
  base_backup: backup1
)
```

### List Backups

```elixir
backups = BackupService.list_backups(store, "app-backups")

Enum.each(backups, fn backup ->
  IO.puts("Backup: #{backup.id}")
  IO.puts("  Timestamp: #{backup.timestamp}")
  IO.puts("  Files: #{backup.file_count}")
  IO.puts("  Size: #{backup.total_size} bytes")
  IO.puts("  Compressed: #{backup.compressed}")
  IO.puts("  Incremental: #{backup.incremental}")
end)
```

### Restore Backup

```elixir
# Restore to original location
:ok = BackupService.restore(store, backup_id, "/data")

# Restore to different location
:ok = BackupService.restore(store, backup_id, "/restore-location",
  overwrite: true,   # Overwrite existing files
  verify: true       # Verify integrity after restore
)
```

### Cleanup Old Backups

```elixir
# Keep backups from last 7 days
{:ok, deleted} = BackupService.cleanup(store, "app-backups", keep_days: 7)
IO.puts("Deleted #{deleted} old backups")

# Keep last 10 backups
{:ok, deleted} = BackupService.cleanup(store, "app-backups", keep_count: 10)

# Dry run (see what would be deleted)
{:ok, count} = BackupService.cleanup(store, "app-backups",
  keep_days: 7,
  dry_run: true
)
IO.puts("Would delete #{count} backups")
```

### Verify Backup Integrity

```elixir
case BackupService.verify(store, backup_id) do
  :ok ->
    IO.puts("Backup is valid")

  {:error, reason} ->
    IO.puts("Backup is corrupted: #{inspect(reason)}")
end
```

## Use Cases

### Automated Daily Backups

```elixir
defmodule DailyBackup do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    schedule_backup()
    {:ok, opts}
  end

  def handle_info(:backup, state) do
    store = state.store
    source = state.source_dir
    prefix = state.backup_prefix

    case BackupService.backup(store, source, prefix, compression: true) do
      {:ok, backup_id} ->
        Logger.info("Daily backup completed: #{backup_id}")

        # Cleanup old backups (keep 30 days)
        BackupService.cleanup(store, prefix, keep_days: 30)

      {:error, reason} ->
        Logger.error("Daily backup failed: #{inspect(reason)}")
    end

    schedule_backup()
    {:noreply, state}
  end

  defp schedule_backup do
    # Run daily at 2 AM
    Process.send_after(self(), :backup, 24 * 60 * 60 * 1000)
  end
end
```

### Database Backup

```elixir
defmodule DatabaseBackup do
  def backup_postgres(store, db_name, backup_prefix) do
    # Export database to file
    dump_file = "/tmp/#{db_name}_#{System.system_time()}.sql"
    System.cmd("pg_dump", ["-f", dump_file, db_name])

    # Upload to object storage
    {:ok, backup_id} = BackupService.backup(store, dump_file, backup_prefix,
      compression: true
    )

    # Cleanup local file
    File.rm(dump_file)

    {:ok, backup_id}
  end

  def restore_postgres(store, backup_id, db_name) do
    restore_dir = "/tmp/restore_#{System.system_time()}"

    # Download backup
    :ok = BackupService.restore(store, backup_id, restore_dir)

    # Find SQL file
    [sql_file] = Path.wildcard("#{restore_dir}/*.sql")

    # Restore database
    System.cmd("psql", ["-f", sql_file, db_name])

    # Cleanup
    File.rm_rf(restore_dir)

    :ok
  end
end
```

### Disaster Recovery

```elixir
defmodule DisasterRecovery do
  @critical_dirs [
    "/etc",
    "/var/www",
    "/home/app/config"
  ]

  def full_system_backup(store) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    prefix = "disaster-recovery/#{timestamp}"

    # Backup all critical directories
    Enum.each(@critical_dirs, fn dir ->
      {:ok, _} = BackupService.backup(store, dir, "#{prefix}/#{Path.basename(dir)}",
        compression: true,
        parallel: 8
      )
    end)

    {:ok, prefix}
  end

  def restore_system(store, backup_prefix) do
    # Restore all directories
    Enum.each(@critical_dirs, fn dir ->
      backup_path = "#{backup_prefix}/#{Path.basename(dir)}"
      BackupService.restore(store, backup_path, dir, overwrite: false)
    end)

    :ok
  end
end
```

## Performance Tips

1. **Use compression for text files**: Compresses 70-90% for logs, configs, code
2. **Use parallel uploads**: 4-8 parallel uploads for optimal throughput
3. **Incremental backups**: Save time and bandwidth by backing up only changes
4. **Exclude unnecessary files**: .git, node_modules, logs, cache directories
5. **Schedule during off-peak hours**: Run backups when system load is low

## Running Tests

```bash
mix test
```

## License

Same as ObjectStoreX (Apache 2.0)
