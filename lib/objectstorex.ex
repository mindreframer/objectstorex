defmodule ObjectStoreX do
  @moduledoc """
  Unified object storage for AWS S3, Azure Blob, GCS, and local filesystem.

  Provides a consistent API across multiple cloud storage providers and local storage.
  Built on top of the Rust `object_store` crate via Rustler NIFs.

  ## Supported Providers

  - `:s3` - Amazon S3
  - `:azure` - Azure Blob Storage
  - `:gcs` - Google Cloud Storage
  - `:local` - Local filesystem
  - `:memory` - In-memory storage (for testing)

  ## Example

      # Create an in-memory store for testing
      {:ok, store} = ObjectStoreX.new(:memory)

      # Store some data
      :ok = ObjectStoreX.put(store, "test.txt", "Hello, World!")

      # Retrieve it
      {:ok, data} = ObjectStoreX.get(store, "test.txt")
      # => "Hello, World!"

      # Get metadata
      {:ok, meta} = ObjectStoreX.head(store, "test.txt")
      # => %{location: "test.txt", size: 13, ...}

      # Delete it
      :ok = ObjectStoreX.delete(store, "test.txt")

  ## Error Handling

  All functions return tagged tuples for error handling:
  - `{:ok, result}` on success
  - `{:error, reason}` on failure

  For detailed information about error types and handling patterns,
  see `ObjectStoreX.Error`.
  """

  alias ObjectStoreX.Native

  @type store :: reference()
  @type path :: String.t()
  @type provider :: :s3 | :azure | :gcs | :local | :memory
  @type metadata :: %{
          location: String.t(),
          last_modified: String.t(),
          size: non_neg_integer(),
          etag: String.t() | nil
        }

  @doc """
  Create a new storage provider.

  ## Examples

      # S3
      {:ok, store} = ObjectStoreX.new(:s3,
        bucket: "my-bucket",
        region: "us-east-1",
        access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
      )

      # Azure
      {:ok, store} = ObjectStoreX.new(:azure,
        account: "myaccount",
        container: "mycontainer",
        access_key: System.get_env("AZURE_STORAGE_KEY")
      )

      # GCS
      {:ok, store} = ObjectStoreX.new(:gcs,
        bucket: "my-gcs-bucket",
        service_account_key: File.read!("credentials.json")
      )

      # Local filesystem
      {:ok, store} = ObjectStoreX.new(:local, path: "/tmp/storage")

      # In-memory (for testing)
      {:ok, store} = ObjectStoreX.new(:memory)
  """
  @spec new(provider(), keyword()) :: {:ok, store()} | {:error, term()}
  @spec new(provider()) :: {:ok, store()} | {:error, term()}

  def new(:s3, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    region = Keyword.fetch!(opts, :region)
    access_key_id = Keyword.get(opts, :access_key_id)
    secret_access_key = Keyword.get(opts, :secret_access_key)

    case Native.new_s3(bucket, region, access_key_id, secret_access_key) do
      store when is_reference(store) -> {:ok, store}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def new(:azure, opts) do
    account = Keyword.fetch!(opts, :account)
    container = Keyword.fetch!(opts, :container)
    access_key = Keyword.get(opts, :access_key)

    case Native.new_azure(account, container, access_key) do
      store when is_reference(store) -> {:ok, store}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def new(:gcs, opts) do
    bucket = Keyword.fetch!(opts, :bucket)
    service_account_key = Keyword.get(opts, :service_account_key)

    case Native.new_gcs(bucket, service_account_key) do
      store when is_reference(store) -> {:ok, store}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def new(:local, opts) do
    path = Keyword.fetch!(opts, :path)

    case Native.new_local(path) do
      store when is_reference(store) -> {:ok, store}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def new(:memory) do
    case Native.new_memory() do
      store when is_reference(store) -> {:ok, store}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @type put_result :: %{
          etag: String.t(),
          version: String.t()
        }

  @doc """
  Upload an object to storage.

  ## Options

  - `:mode` - Write mode (default: `:overwrite`)
    - `:overwrite` - Always write, overwriting any existing object
    - `:create` - Only write if the object doesn't exist (returns `{:error, :already_exists}` if exists)
    - `{:update, %{etag: ..., version: ...}}` - CAS operation, only write if version matches
  - `:content_type` - MIME type (e.g., "application/json")
  - `:content_encoding` - Encoding (e.g., "gzip")
  - `:content_disposition` - Download behavior (e.g., "attachment; filename=file.pdf")
  - `:cache_control` - Cache directives (e.g., "max-age=3600")
  - `:content_language` - Language (e.g., "en-US")
  - `:tags` - Object tags as a map (AWS/GCS only)

  ## Examples

      # Simple put (overwrite)
      :ok = ObjectStoreX.put(store, "file.txt", "Hello, World!")

      # Create only (distributed lock)
      case ObjectStoreX.put(store, "lock.txt", "locked", mode: :create) do
        {:ok, _meta} -> :acquired
        {:error, :already_exists} -> :already_locked
      end

      # Compare-and-swap (optimistic locking)
      {:ok, meta} = ObjectStoreX.head(store, "counter.json")
      case ObjectStoreX.put(store, "counter.json", new_data,
                            mode: {:update, %{etag: meta[:etag], version: meta[:version]}}) do
        {:ok, _meta} -> :success
        {:error, :precondition_failed} -> :retry
      end

      # Upload with content type
      ObjectStoreX.put(store, "data.json", json_data, content_type: "application/json")

      # Upload with attributes
      ObjectStoreX.put(store, "report.pdf", pdf_data,
        content_type: "application/pdf",
        content_disposition: "attachment; filename=report.pdf",
        cache_control: "max-age=3600"
      )

      # Upload with tags (AWS/GCS)
      ObjectStoreX.put(store, "backup.zip", data,
        tags: %{"environment" => "production", "backup-type" => "daily"}
      )
  """
  @spec put(store(), path(), binary(), keyword()) ::
          :ok | {:ok, put_result()} | {:error, term()}
  def put(store, path, data, opts \\ [])

  def put(store, path, data, []) when is_binary(data) do
    case Native.put(store, path, data) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def put(store, path, data, opts) when is_binary(data) and is_list(opts) do
    mode = Keyword.get(opts, :mode, :overwrite)

    # Check if attributes are provided
    has_attributes = Keyword.has_key?(opts, :content_type) or
                     Keyword.has_key?(opts, :content_encoding) or
                     Keyword.has_key?(opts, :content_disposition) or
                     Keyword.has_key?(opts, :cache_control) or
                     Keyword.has_key?(opts, :content_language) or
                     Keyword.has_key?(opts, :tags)

    if has_attributes do
      # Use put_with_attributes for full control
      attributes = %ObjectStoreX.Attributes{
        content_type: Keyword.get(opts, :content_type),
        content_encoding: Keyword.get(opts, :content_encoding),
        content_disposition: Keyword.get(opts, :content_disposition),
        cache_control: Keyword.get(opts, :cache_control),
        content_language: Keyword.get(opts, :content_language)
      }

      tags = Keyword.get(opts, :tags, %{})
               |> Map.to_list()

      case Native.put_with_attributes(store, path, data, mode, attributes, tags) do
        {:ok, etag, version} ->
          {:ok, %{etag: etag, version: version}}

        :already_exists ->
          {:error, :already_exists}

        :precondition_failed ->
          {:error, :precondition_failed}

        error ->
          {:error, error}
      end
    else
      # Use simple put_with_mode for backwards compatibility
      case Native.put_with_mode(store, path, data, mode) do
        {:ok, etag, version} ->
          {:ok, %{etag: etag, version: version}}

        :already_exists ->
          {:error, :already_exists}

        :precondition_failed ->
          {:error, :precondition_failed}

        error ->
          {:error, error}
      end
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Download an object from storage with optional conditional requests.

  ## Options

  Supports HTTP-style conditional requests for caching and consistency:
  - `:if_match` - Only return if ETag matches (HTTP If-Match)
  - `:if_none_match` - Only return if ETag differs (HTTP If-None-Match)
  - `:if_modified_since` - Only return if modified after date (DateTime or Unix timestamp)
  - `:if_unmodified_since` - Only return if not modified since date (DateTime or Unix timestamp)
  - `:range` - Byte range `{start, end}` or `%ObjectStoreX.Range{}`
  - `:version` - Specific object version
  - `:head` - Return metadata only (no content)

  ## Examples

      # Simple get
      {:ok, data} = ObjectStoreX.get(store, "file.txt")

      # HTTP cache validation
      case ObjectStoreX.get(store, "file.txt", if_none_match: cached_etag) do
        {:ok, data, meta} -> {:modified, data, meta}
        {:error, :not_modified} -> :use_cache
      end

      # Consistent read with ETag
      {:ok, meta} = ObjectStoreX.head(store, "config.json")
      case ObjectStoreX.get(store, "config.json", if_match: meta[:etag]) do
        {:ok, data, _meta} -> {:ok, data}
        {:error, :precondition_failed} -> :retry
      end

      # Range read
      {:ok, data, meta} = ObjectStoreX.get(store, "large.bin", range: {0, 1000})

      # Head-only (metadata without content)
      {:ok, _empty, meta} = ObjectStoreX.get(store, "file.txt", head: true)
  """
  @spec get(store(), path(), keyword()) ::
    {:ok, binary()} | {:ok, binary(), metadata()} | {:error, term()}
  def get(store, path, opts \\ [])

  def get(store, path, []) do
    case Native.get(store, path) do
      data when is_binary(data) -> {:ok, data}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  def get(store, path, opts) when is_list(opts) do
    # Convert keyword options to GetOptions struct
    get_options = %ObjectStoreX.GetOptions{
      if_match: Keyword.get(opts, :if_match),
      if_none_match: Keyword.get(opts, :if_none_match),
      if_modified_since: convert_datetime_to_timestamp(Keyword.get(opts, :if_modified_since)),
      if_unmodified_since: convert_datetime_to_timestamp(Keyword.get(opts, :if_unmodified_since)),
      range: convert_range(Keyword.get(opts, :range)),
      version: Keyword.get(opts, :version),
      head: Keyword.get(opts, :head, false)
    }

    case Native.get_with_options(store, path, get_options) do
      {:ok, data, meta} when is_map(meta) ->
        # Convert charlist to binary if needed
        binary_data = if is_list(data), do: :erlang.list_to_binary(data), else: data
        {:ok, binary_data, meta}
      :not_found ->
        {:error, :not_found}
      :not_modified ->
        {:error, :not_modified}
      :precondition_failed ->
        {:error, :precondition_failed}
      error ->
        {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  # Convert DateTime to Unix timestamp, or pass through integer timestamps
  defp convert_datetime_to_timestamp(nil), do: nil
  defp convert_datetime_to_timestamp(%DateTime{} = dt), do: DateTime.to_unix(dt)
  defp convert_datetime_to_timestamp(ts) when is_integer(ts), do: ts

  # Convert range tuple or Range struct to Range struct
  defp convert_range(nil), do: nil
  defp convert_range({start, end_pos}), do: %ObjectStoreX.Range{start: start, end: end_pos}
  defp convert_range(%ObjectStoreX.Range{} = range), do: range

  @doc """
  Delete an object from storage.

  ## Examples

      :ok = ObjectStoreX.delete(store, "file.txt")
  """
  @spec delete(store(), path()) :: :ok | {:error, term()}
  def delete(store, path) do
    case Native.delete(store, path) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Get object metadata without downloading content.

  ## Examples

      {:ok, meta} = ObjectStoreX.head(store, "file.txt")
      # %{location: "file.txt", size: 1024, ...}
  """
  @spec head(store(), path()) :: {:ok, metadata()} | {:error, term()}
  def head(store, path) do
    case Native.head(store, path) do
      meta when is_map(meta) -> {:ok, meta}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Copy an object within storage (server-side).

  ## Examples

      :ok = ObjectStoreX.copy(store, "source.txt", "destination.txt")
  """
  @spec copy(store(), path(), path()) :: :ok | {:error, term()}
  def copy(store, from, to) do
    case Native.copy(store, from, to) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Rename an object (server-side move).

  ## Examples

      :ok = ObjectStoreX.rename(store, "old.txt", "new.txt")
  """
  @spec rename(store(), path(), path()) :: :ok | {:error, term()}
  def rename(store, from, to) do
    case Native.rename(store, from, to) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Copy an object only if the destination doesn't exist (atomic where supported).

  Provider support:
  - Azure: ✅ Native atomic copy_if_not_exists
  - GCS: ✅ Native atomic copy_if_not_exists
  - Local: ✅ Atomic via filesystem operations
  - Memory: ✅ Atomic via in-memory checks
  - S3: ❌ Not supported (returns `{:error, :not_supported}`)

  For S3, use a manual check-then-copy pattern:

      case ObjectStoreX.head(store, destination) do
        {:error, :not_found} ->
          ObjectStoreX.copy(store, source, destination)
        {:ok, _meta} ->
          {:error, :already_exists}
      end

  ## Examples

      # Atomic copy (Azure/GCS/Local/Memory)
      case ObjectStoreX.copy_if_not_exists(store, "source.txt", "backup.txt") do
        :ok -> :copied
        {:error, :already_exists} -> :destination_exists
        {:error, :not_supported} -> :use_manual_pattern
      end

      # Distributed lock backup
      case ObjectStoreX.copy_if_not_exists(store, "lock.txt", "lock-backup.txt") do
        :ok -> :backup_created
        {:error, :already_exists} -> :backup_already_exists
      end
  """
  @spec copy_if_not_exists(store(), path(), path()) :: :ok | {:error, term()}
  def copy_if_not_exists(store, from, to) do
    case Native.copy_if_not_exists(store, from, to) do
      :ok -> :ok
      :already_exists -> {:error, :already_exists}
      :not_supported -> {:error, :not_supported}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Rename an object only if the destination doesn't exist (atomic where supported).

  This is implemented as copy_if_not_exists followed by delete of the source.
  The operation is only atomic if the underlying provider supports atomic copy_if_not_exists.

  Provider support:
  - Azure: ✅ Atomic
  - GCS: ✅ Atomic
  - Local: ✅ Atomic
  - Memory: ✅ Atomic
  - S3: ❌ Not supported (returns `{:error, :not_supported}`)

  ## Examples

      # Atomic rename (Azure/GCS/Local/Memory)
      case ObjectStoreX.rename_if_not_exists(store, "old.txt", "new.txt") do
        :ok -> :renamed
        {:error, :already_exists} -> :destination_exists
        {:error, :not_supported} -> :use_manual_pattern
      end

      # Safe rename with collision detection
      case ObjectStoreX.rename_if_not_exists(store, "temp.txt", "final.txt") do
        :ok -> :moved
        {:error, :already_exists} -> :collision
        {:error, :not_found} -> :source_missing
      end
  """
  @spec rename_if_not_exists(store(), path(), path()) :: :ok | {:error, term()}
  def rename_if_not_exists(store, from, to) do
    case Native.rename_if_not_exists(store, from, to) do
      :ok -> :ok
      :already_exists -> {:error, :already_exists}
      :not_supported -> {:error, :not_supported}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Fetch multiple byte ranges from an object in a single operation.

  Useful for reading file headers, footers, and metadata without downloading
  the entire file (e.g., Parquet files, video files).

  ## Examples

      # Read header and footer
      {:ok, [header, footer]} = ObjectStoreX.get_ranges(store, "data.parquet", [
        {0, 1000},           # First 1000 bytes
        {9000, 10000}        # Bytes 9000-10000
      ])

      # Read specific sections
      {:ok, chunks} = ObjectStoreX.get_ranges(store, "video.mp4", [
        {0, 100},            # Header
        {500, 600},          # Metadata
        {1000, 2000}         # Preview section
      ])
  """
  @spec get_ranges(store(), path(), [{non_neg_integer(), non_neg_integer()}]) ::
          {:ok, [binary()]} | {:error, term()}
  def get_ranges(store, path, ranges) when is_list(ranges) do
    case Native.get_ranges(store, path, ranges) do
      binaries when is_list(binaries) -> {:ok, binaries}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Delete multiple objects in bulk with automatic batching.

  Provider-specific batching:
  - S3: Up to 1000 objects per request
  - Azure: Individual deletes (parallelized)
  - GCS: Batch API (up to 100 objects per request)

  ## Examples

      # Delete many objects
      paths = ["file1.txt", "file2.txt", "file3.txt"]
      {:ok, 3, []} = ObjectStoreX.delete_many(store, paths)

      # Handle partial failures
      result = ObjectStoreX.delete_many(store, paths)
      case result do
        {:ok, succeeded, failed} ->
          IO.puts("Deleted: \#{succeeded}, Failed: \#{length(failed)}")
        {:error, reason} ->
          IO.puts("Error: \#{reason}")
      end
  """
  @spec delete_many(store(), [path()]) :: {:ok, non_neg_integer(), list()} | {:error, term()}
  def delete_many(store, paths) when is_list(paths) do
    case Native.delete_many(store, paths) do
      {succeeded, failed} when is_integer(succeeded) and is_list(failed) ->
        {:ok, succeeded, failed}

      error ->
        {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  List objects with delimiter, returning objects and common prefixes separately.

  This simulates a directory structure by grouping objects by common prefixes.
  The delimiter is always "/" (forward slash).

  ## Examples

      {:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store, prefix: "data/")

      # objects = [%{location: "data/file.txt", ...}]
      # prefixes = ["data/2024/", "data/2025/"]

      # List root level
      {:ok, objects, prefixes} = ObjectStoreX.list_with_delimiter(store)

  ## Options

  * `:prefix` - Optional prefix to filter objects (default: nil)

  ## Returns

  A tuple of `{:ok, objects, prefixes}` where:
  - `objects` is a list of metadata maps for objects at the current level
  - `prefixes` is a list of string prefixes (subdirectories)
  """
  @spec list_with_delimiter(store(), keyword()) ::
          {:ok, [metadata()], [String.t()]} | {:error, term()}
  def list_with_delimiter(store, opts \\ []) do
    prefix = Keyword.get(opts, :prefix)

    case Native.list_with_delimiter(store, prefix) do
      {objects, prefixes} when is_list(objects) and is_list(prefixes) ->
        {:ok, objects, prefixes}

      error ->
        {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end
end
