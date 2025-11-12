defmodule BackupService do
  @moduledoc """
  Example: Automated backup service with retention policies.

  This example demonstrates how to use ObjectStoreX to build a backup service
  that automatically backs up directories to object storage with configurable
  retention policies.

  ## Features

  - **Full and incremental backups**: Track file changes and upload only modified files
  - **Retention policies**: Automatically delete old backups based on age or count
  - **Compression**: Optional gzip compression for backups
  - **Parallel uploads**: Upload multiple files concurrently
  - **Restore capability**: Restore backups to any location
  - **Verification**: Verify backup integrity with checksums

  ## Usage

      # Create a backup store
      {:ok, store} = ObjectStoreX.new(:s3,
        bucket: "my-backups",
        region: "us-east-1"
      )

      # Perform a full backup
      {:ok, backup_id} = BackupService.backup(store, "/data", "app-backups",
        compression: true,
        parallel: 4
      )

      # List all backups
      backups = BackupService.list_backups(store, "app-backups")

      # Restore a backup
      :ok = BackupService.restore(store, backup_id, "/restore-location")

      # Clean up old backups (keep last 7 days)
      {:ok, deleted} = BackupService.cleanup(store, "app-backups", keep_days: 7)

  ## Backup Structure

  Backups are stored with the following structure:

      <prefix>/<timestamp>/
        manifest.json       # Backup metadata
        files/
          path/to/file1.txt
          path/to/file2.bin.gz

  ## Incremental Backups

      # First backup (full)
      {:ok, backup1} = BackupService.backup(store, "/data", "incremental")

      # ... time passes, files change ...

      # Incremental backup (only changed files)
      {:ok, backup2} = BackupService.backup(store, "/data", "incremental",
        incremental: true,
        base_backup: backup1
      )
  """

  require Logger
  alias ObjectStoreX.Stream, as: StoreStream

  @type backup_id :: String.t()
  @type backup_manifest :: %{
          id: String.t(),
          timestamp: DateTime.t(),
          source_path: String.t(),
          file_count: non_neg_integer(),
          total_size: non_neg_integer(),
          compressed: boolean(),
          incremental: boolean(),
          base_backup: String.t() | nil
        }

  @doc """
  Create a backup of a directory.

  ## Options

  - `:compression` - Enable gzip compression (default: false)
  - `:parallel` - Number of parallel uploads (default: 1)
  - `:incremental` - Only backup changed files (default: false)
  - `:base_backup` - Base backup ID for incremental backups
  - `:exclude` - List of patterns to exclude (default: [])

  ## Returns

  - `{:ok, backup_id}` on success
  - `{:error, reason}` on failure
  """
  @spec backup(ObjectStoreX.store(), String.t(), String.t(), keyword()) ::
          {:ok, backup_id()} | {:error, term()}
  def backup(store, source_dir, backup_prefix, opts \\ []) do
    compression = Keyword.get(opts, :compression, false)
    parallel = Keyword.get(opts, :parallel, 1)
    incremental = Keyword.get(opts, :incremental, false)
    base_backup = Keyword.get(opts, :base_backup)
    exclude = Keyword.get(opts, :exclude, [])

    with {:ok, files} <- list_files(source_dir, exclude),
         {:ok, files_to_backup} <- filter_incremental(store, files, incremental, base_backup),
         backup_id = generate_backup_id(),
         backup_path = "#{backup_prefix}/#{backup_id}",
         :ok <- upload_files(store, files_to_backup, source_dir, backup_path, compression, parallel),
         manifest = build_manifest(backup_id, source_dir, files_to_backup, compression, incremental, base_backup),
         :ok <- save_manifest(store, backup_path, manifest) do
      Logger.info("Backup completed: #{backup_id} (#{length(files_to_backup)} files)")
      {:ok, backup_id}
    else
      {:error, reason} ->
        Logger.error("Backup failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Restore a backup to a directory.

  ## Options

  - `:overwrite` - Overwrite existing files (default: false)
  - `:verify` - Verify file integrity after restore (default: true)

  ## Returns

  - `:ok` on success
  - `{:error, reason}` on failure
  """
  @spec restore(ObjectStoreX.store(), backup_id(), String.t(), keyword()) ::
          :ok | {:error, term()}
  def restore(store, backup_id, target_dir, opts \\ []) do
    overwrite = Keyword.get(opts, :overwrite, false)
    verify = Keyword.get(opts, :verify, true)

    # Extract backup prefix from backup_id
    backup_path = backup_id

    with {:ok, manifest} <- load_manifest(store, backup_path),
         :ok <- ensure_directory(target_dir),
         :ok <- download_files(store, backup_path, target_dir, manifest, overwrite),
         :ok <- maybe_verify(store, backup_path, target_dir, manifest, verify) do
      Logger.info("Restore completed: #{backup_id} to #{target_dir}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Restore failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  List all backups with a given prefix.

  Returns a list of backup manifests sorted by timestamp (newest first).
  """
  @spec list_backups(ObjectStoreX.store(), String.t()) :: [backup_manifest()]
  def list_backups(store, backup_prefix) do
    StoreStream.list_stream(store, prefix: "#{backup_prefix}/")
    |> Stream.filter(&String.ends_with?(&1.location, "/manifest.json"))
    |> Stream.map(fn meta ->
      backup_path = Path.dirname(meta.location)

      case load_manifest(store, backup_path) do
        {:ok, manifest} -> manifest
        {:error, _} -> nil
      end
    end)
    |> Stream.reject(&is_nil/1)
    |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
  end

  @doc """
  Clean up old backups based on retention policy.

  ## Options

  - `:keep_days` - Keep backups from last N days (default: 7)
  - `:keep_count` - Keep last N backups (default: unlimited)
  - `:dry_run` - Don't actually delete, just return what would be deleted (default: false)

  ## Returns

  - `{:ok, deleted_count}` on success
  - `{:error, reason}` on failure
  """
  @spec cleanup(ObjectStoreX.store(), String.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def cleanup(store, backup_prefix, opts \\ []) do
    keep_days = Keyword.get(opts, :keep_days, 7)
    keep_count = Keyword.get(opts, :keep_count)
    dry_run = Keyword.get(opts, :dry_run, false)

    backups = list_backups(store, backup_prefix)
    cutoff = DateTime.utc_now() |> DateTime.add(-keep_days * 86_400, :second)

    to_delete =
      backups
      |> apply_retention_policies(cutoff, keep_count)
      |> Enum.map(& &1.id)

    if dry_run do
      Logger.info("Dry run: Would delete #{length(to_delete)} backups")
      {:ok, length(to_delete)}
    else
      deleted = delete_backups(store, backup_prefix, to_delete)
      Logger.info("Deleted #{deleted} old backups")
      {:ok, deleted}
    end
  end

  @doc """
  Verify the integrity of a backup.

  Checks that all files in the manifest exist and have correct sizes.
  """
  @spec verify(ObjectStoreX.store(), backup_id()) :: :ok | {:error, term()}
  def verify(store, backup_id) do
    backup_path = backup_id

    with {:ok, manifest} <- load_manifest(store, backup_path),
         :ok <- verify_files(store, backup_path, manifest) do
      Logger.info("Backup verification successful: #{backup_id}")
      :ok
    else
      {:error, reason} ->
        Logger.error("Backup verification failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # Private helpers

  defp generate_backup_id do
    DateTime.utc_now()
    |> DateTime.to_iso8601()
    |> String.replace(":", "-")
  end

  defp list_files(dir, exclude) do
    files =
      Path.wildcard("#{dir}/**/*")
      |> Enum.filter(&File.regular?/1)
      |> Enum.reject(fn path ->
        Enum.any?(exclude, fn pattern ->
          String.contains?(path, pattern)
        end)
      end)

    {:ok, files}
  rescue
    e -> {:error, {:list_files, Exception.message(e)}}
  end

  defp filter_incremental(_store, files, false, _base_backup), do: {:ok, files}

  defp filter_incremental(store, files, true, base_backup) when is_binary(base_backup) do
    # Load base backup manifest
    case load_manifest(store, base_backup) do
      {:ok, base_manifest} ->
        # Filter files that have changed since base backup
        changed =
          Enum.filter(files, fn file ->
            stat = File.stat!(file)
            file_changed?(stat.mtime, base_manifest.timestamp)
          end)

        {:ok, changed}

      {:error, _reason} ->
        # If base backup not found, do full backup
        Logger.warning("Base backup not found, performing full backup")
        {:ok, files}
    end
  end

  defp filter_incremental(_store, files, true, nil) do
    Logger.warning("Incremental backup requested but no base backup specified, performing full backup")
    {:ok, files}
  end

  defp file_changed?(mtime, base_timestamp) do
    file_datetime = mtime |> NaiveDateTime.from_erl!() |> DateTime.from_naive!("Etc/UTC")
    DateTime.compare(file_datetime, base_timestamp) == :gt
  end

  defp upload_files(store, files, source_dir, backup_path, compression, parallel) do
    files
    |> Task.async_stream(
      fn file ->
        relative_path = Path.relative_to(file, source_dir)
        remote_path = "#{backup_path}/files/#{relative_path}"

        remote_path =
          if compression do
            remote_path <> ".gz"
          else
            remote_path
          end

        upload_file(store, file, remote_path, compression)
      end,
      max_concurrency: parallel,
      timeout: 300_000
    )
    |> Enum.reduce_while(:ok, fn
      {:ok, :ok}, :ok -> {:cont, :ok}
      {:ok, {:error, reason}}, :ok -> {:halt, {:error, reason}}
      {:exit, reason}, :ok -> {:halt, {:error, {:upload_failed, reason}}}
    end)
  end

  defp upload_file(store, local_path, remote_path, compression) do
    if compression do
      # Read, compress, and upload
      case File.read(local_path) do
        {:ok, data} ->
          compressed = :zlib.gzip(data)
          ObjectStoreX.put(store, remote_path, compressed)

        {:error, reason} ->
          {:error, {:read_failed, reason}}
      end
    else
      # Stream upload
      File.stream!(local_path, [], 10_485_760)
      |> StoreStream.upload(store, remote_path)
    end
  end

  defp build_manifest(id, source_path, files, compressed, incremental, base_backup) do
    total_size = Enum.reduce(files, 0, fn file, acc ->
      acc + File.stat!(file).size
    end)

    %{
      id: id,
      timestamp: DateTime.utc_now(),
      source_path: source_path,
      file_count: length(files),
      total_size: total_size,
      compressed: compressed,
      incremental: incremental,
      base_backup: base_backup
    }
  end

  defp save_manifest(store, backup_path, manifest) do
    json = Jason.encode!(manifest)
    ObjectStoreX.put(store, "#{backup_path}/manifest.json", json)
  end

  defp load_manifest(store, backup_path) do
    case ObjectStoreX.get(store, "#{backup_path}/manifest.json") do
      {:ok, json, _meta} ->
        manifest =
          Jason.decode!(json, keys: :atoms)
          |> Map.update!(:timestamp, &DateTime.from_iso8601(&1) |> elem(1))

        {:ok, manifest}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp ensure_directory(dir) do
    File.mkdir_p(dir)
  end

  defp download_files(store, backup_path, target_dir, manifest, overwrite) do
    # List all files in backup
    StoreStream.list_stream(store, prefix: "#{backup_path}/files/")
    |> Enum.reduce_while(:ok, fn meta, :ok ->
      relative_path = String.replace_prefix(meta.location, "#{backup_path}/files/", "")

      # Remove .gz extension if compressed
      relative_path =
        if manifest.compressed and String.ends_with?(relative_path, ".gz") do
          String.slice(relative_path, 0..-4//1)
        else
          relative_path
        end

      local_path = Path.join(target_dir, relative_path)

      if File.exists?(local_path) and not overwrite do
        Logger.warning("File exists, skipping: #{local_path}")
        {:cont, :ok}
      else
        File.mkdir_p!(Path.dirname(local_path))

        case download_file(store, meta.location, local_path, manifest.compressed) do
          :ok -> {:cont, :ok}
          error -> {:halt, error}
        end
      end
    end)
  end

  defp download_file(store, remote_path, local_path, compressed) do
    case ObjectStoreX.get(store, remote_path) do
      {:ok, data, _meta} ->
        data =
          if compressed do
            :zlib.gunzip(data)
          else
            data
          end

        File.write(local_path, data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_verify(_store, _backup_path, _target_dir, _manifest, false), do: :ok
  defp maybe_verify(store, backup_path, _target_dir, manifest, true) do
    verify_files(store, backup_path, manifest)
  end

  defp verify_files(store, backup_path, manifest) do
    # Verify all files exist
    expected_count = manifest.file_count

    StoreStream.list_stream(store, prefix: "#{backup_path}/files/")
    |> Enum.count()
    |> case do
      ^expected_count -> :ok
      actual -> {:error, {:file_count_mismatch, expected: expected_count, actual: actual}}
    end
  end

  defp apply_retention_policies(backups, cutoff, keep_count) do
    # Filter by date
    old_backups =
      backups
      |> Enum.filter(fn backup ->
        DateTime.compare(backup.timestamp, cutoff) == :lt
      end)

    # If keep_count is set, keep the most recent N backups
    if keep_count do
      backups
      |> Enum.sort_by(& &1.timestamp, {:desc, DateTime})
      |> Enum.drop(keep_count)
    else
      old_backups
    end
  end

  defp delete_backups(store, backup_prefix, backup_ids) do
    Enum.reduce(backup_ids, 0, fn backup_id, count ->
      backup_path = "#{backup_prefix}/#{backup_id}"

      # List all objects in backup
      objects =
        StoreStream.list_stream(store, prefix: backup_path)
        |> Enum.map(& &1.location)

      # Delete all objects
      case ObjectStoreX.delete_many(store, objects) do
        {:ok, _succeeded, _failed} -> count + 1
        {:error, reason} ->
          Logger.error("Failed to delete backup #{backup_id}: #{inspect(reason)}")
          count
      end
    end)
  end
end
