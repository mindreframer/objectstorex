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
  see `ObjectStoreX.Errors`.
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

  @doc """
  Upload an object to storage.

  ## Examples

      :ok = ObjectStoreX.put(store, "file.txt", "Hello, World!")
  """
  @spec put(store(), path(), binary()) :: :ok | {:error, term()}
  def put(store, path, data) when is_binary(data) do
    case Native.put(store, path, data) do
      :ok -> :ok
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  @doc """
  Download an object from storage.

  ## Examples

      {:ok, data} = ObjectStoreX.get(store, "file.txt")
  """
  @spec get(store(), path()) :: {:ok, binary()} | {:error, term()}
  def get(store, path) do
    case Native.get(store, path) do
      data when is_binary(data) -> {:ok, data}
      :not_found -> {:error, :not_found}
      error -> {:error, error}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

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
end
