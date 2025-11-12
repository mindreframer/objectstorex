# Configuration Guide

This guide covers detailed configuration options for all supported storage providers.

## Table of Contents

- [AWS S3](#aws-s3)
- [Azure Blob Storage](#azure-blob-storage)
- [Google Cloud Storage](#google-cloud-storage)
- [Local Filesystem](#local-filesystem)
- [In-Memory Storage](#in-memory-storage)
- [Credential Management](#credential-management)
- [Configuration Best Practices](#configuration-best-practices)

## AWS S3

Amazon S3 and S3-compatible services (MinIO, Cloudflare R2, DigitalOcean Spaces, etc.).

### Basic Configuration

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1"
)
```

### With Explicit Credentials

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1",
  access_key_id: "AKIAIOSFODNN7EXAMPLE",
  secret_access_key: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
)
```

### Using Environment Variables

```elixir
# Reads from AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1",
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
)
```

### S3-Compatible Services

#### MinIO

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1",
  endpoint: "http://localhost:9000",
  access_key_id: "minioadmin",
  secret_access_key: "minioadmin"
)
```

#### Cloudflare R2

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "auto",
  endpoint: "https://<account-id>.r2.cloudflarestorage.com",
  access_key_id: System.get_env("R2_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("R2_SECRET_ACCESS_KEY")
)
```

#### DigitalOcean Spaces

```elixir
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-space",
  region: "nyc3",
  endpoint: "https://nyc3.digitaloceanspaces.com",
  access_key_id: System.get_env("SPACES_ACCESS_KEY"),
  secret_access_key: System.get_env("SPACES_SECRET_KEY")
)
```

### Configuration Options

- **`bucket`** (required) - S3 bucket name
- **`region`** (required) - AWS region (e.g., "us-east-1", "eu-west-1")
- **`access_key_id`** (optional) - AWS access key ID
- **`secret_access_key`** (optional) - AWS secret access key
- **`endpoint`** (optional) - Custom endpoint for S3-compatible services

### IAM Role Credentials

When running on EC2, ECS, or Lambda, ObjectStoreX can use IAM role credentials automatically:

```elixir
# No credentials needed - uses IAM role
{:ok, store} = ObjectStoreX.new(:s3,
  bucket: "my-bucket",
  region: "us-east-1"
)
```

## Azure Blob Storage

Microsoft Azure Blob Storage configuration.

### Basic Configuration

```elixir
{:ok, store} = ObjectStoreX.new(:azure,
  account: "mystorageaccount",
  container: "mycontainer",
  access_key: System.get_env("AZURE_STORAGE_KEY")
)
```

### Using Connection String

```elixir
{:ok, store} = ObjectStoreX.new(:azure,
  account: "mystorageaccount",
  container: "mycontainer",
  connection_string: System.get_env("AZURE_STORAGE_CONNECTION_STRING")
)
```

### Using SAS Token

```elixir
{:ok, store} = ObjectStoreX.new(:azure,
  account: "mystorageaccount",
  container: "mycontainer",
  sas_token: System.get_env("AZURE_SAS_TOKEN")
)
```

### Configuration Options

- **`account`** (required) - Azure storage account name
- **`container`** (required) - Azure blob container name
- **`access_key`** (optional) - Storage account access key
- **`connection_string`** (optional) - Azure storage connection string
- **`sas_token`** (optional) - Shared Access Signature token

### Managed Identity

When running on Azure VMs or App Services, use managed identity:

```elixir
# No credentials needed - uses managed identity
{:ok, store} = ObjectStoreX.new(:azure,
  account: "mystorageaccount",
  container: "mycontainer"
)
```

## Google Cloud Storage

Google Cloud Storage configuration.

### Basic Configuration

```elixir
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket"
)
```

### Using Service Account Key

```elixir
# From file
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket",
  service_account_key: File.read!("credentials.json")
)

# From environment variable
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket",
  service_account_key: System.get_env("GCP_SERVICE_ACCOUNT_KEY")
)
```

### Configuration Options

- **`bucket`** (required) - GCS bucket name
- **`service_account_key`** (optional) - Service account JSON key

### Application Default Credentials

When running on GCP (Compute Engine, Cloud Run, etc.), use ADC:

```elixir
# No credentials needed - uses Application Default Credentials
{:ok, store} = ObjectStoreX.new(:gcs,
  bucket: "my-gcs-bucket"
)
```

## Local Filesystem

Local filesystem storage for development and testing.

### Basic Configuration

```elixir
{:ok, store} = ObjectStoreX.new(:local,
  path: "/tmp/my-storage"
)
```

### Absolute Paths

```elixir
{:ok, store} = ObjectStoreX.new(:local,
  path: "/var/data/storage"
)
```

### Relative Paths

```elixir
# Relative to current working directory
{:ok, store} = ObjectStoreX.new(:local,
  path: "data/storage"
)
```

### Configuration Options

- **`path`** (required) - Root directory for storage

### Behavior

- Automatically creates directories as needed
- Preserves object paths as subdirectories
- Example: `"data/2025/file.txt"` → `/tmp/my-storage/data/2025/file.txt`

## In-Memory Storage

In-memory storage for testing and development.

### Basic Configuration

```elixir
{:ok, store} = ObjectStoreX.new(:memory)
```

### Use Cases

- Unit tests
- Integration tests
- Development without external dependencies
- Temporary data

### Limitations

- Data is lost when the process terminates
- No persistence
- Limited by available RAM

## Credential Management

### Environment Variables

Best practice for storing credentials:

```elixir
# config/runtime.exs
config :my_app, :storage,
  provider: :s3,
  bucket: System.get_env("S3_BUCKET"),
  region: System.get_env("S3_REGION"),
  access_key_id: System.get_env("AWS_ACCESS_KEY_ID"),
  secret_access_key: System.get_env("AWS_SECRET_ACCESS_KEY")
```

Then use in your application:

```elixir
defmodule MyApp.Storage do
  def init do
    config = Application.get_env(:my_app, :storage)

    ObjectStoreX.new(
      config[:provider],
      bucket: config[:bucket],
      region: config[:region],
      access_key_id: config[:access_key_id],
      secret_access_key: config[:secret_access_key]
    )
  end
end
```

### Secrets Management

For production, use a secrets manager:

```elixir
# Using Vault, AWS Secrets Manager, etc.
defmodule MyApp.Storage do
  def init do
    secrets = MyApp.Secrets.fetch!("storage/credentials")

    ObjectStoreX.new(:s3,
      bucket: secrets["bucket"],
      region: secrets["region"],
      access_key_id: secrets["access_key_id"],
      secret_access_key: secrets["secret_access_key"]
    )
  end
end
```

## Configuration Best Practices

### 1. Use Environment-Specific Configuration

```elixir
# config/dev.exs
config :my_app, :storage,
  provider: :local,
  path: "tmp/dev_storage"

# config/test.exs
config :my_app, :storage,
  provider: :memory

# config/prod.exs
config :my_app, :storage,
  provider: :s3,
  bucket: System.get_env("S3_BUCKET"),
  region: System.get_env("S3_REGION")
```

### 2. Initialize Store Once

Create a GenServer or Application supervisor to manage the store:

```elixir
defmodule MyApp.Storage do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_store do
    GenServer.call(__MODULE__, :get_store)
  end

  def init(_opts) do
    config = Application.get_env(:my_app, :storage)
    {:ok, store} = ObjectStoreX.new(config[:provider], Keyword.delete(config, :provider))
    {:ok, %{store: store}}
  end

  def handle_call(:get_store, _from, state) do
    {:reply, state.store, state}
  end
end

# In your application supervisor
children = [
  MyApp.Storage
]
```

### 3. Validate Configuration at Startup

```elixir
defmodule MyApp.Storage do
  def init do
    config = Application.get_env(:my_app, :storage)

    unless config[:bucket] do
      raise "Storage bucket not configured"
    end

    case ObjectStoreX.new(:s3, config) do
      {:ok, store} -> {:ok, store}
      {:error, reason} -> raise "Failed to initialize storage: #{inspect(reason)}"
    end
  end
end
```

### 4. Use Multiple Stores

Different stores for different purposes:

```elixir
defmodule MyApp.Storage do
  def uploads_store do
    {:ok, store} = ObjectStoreX.new(:s3, bucket: "uploads", region: "us-east-1")
    store
  end

  def backups_store do
    {:ok, store} = ObjectStoreX.new(:s3, bucket: "backups", region: "us-west-2")
    store
  end

  def cache_store do
    {:ok, store} = ObjectStoreX.new(:local, path: "/var/cache/app")
    store
  end
end
```

## Troubleshooting

### S3 Connection Issues

```elixir
# Test connectivity
case ObjectStoreX.new(:s3, bucket: "my-bucket", region: "us-east-1") do
  {:ok, store} ->
    case ObjectStoreX.put(store, "test.txt", "test") do
      :ok -> IO.puts "✓ S3 connection working"
      {:error, reason} -> IO.puts "✗ S3 error: #{inspect(reason)}"
    end
  {:error, reason} ->
    IO.puts "✗ Failed to create store: #{inspect(reason)}"
end
```

### Azure Connection Issues

```elixir
# Verify credentials
account = System.get_env("AZURE_STORAGE_ACCOUNT")
key = System.get_env("AZURE_STORAGE_KEY")

unless account && key do
  raise "Missing Azure credentials"
end
```

### GCS Connection Issues

```elixir
# Verify service account key
key_json = System.get_env("GCP_SERVICE_ACCOUNT_KEY")

case Jason.decode(key_json) do
  {:ok, _parsed} -> IO.puts "✓ Valid JSON key"
  {:error, _} -> IO.puts "✗ Invalid JSON key"
end
```

## Next Steps

- [Getting Started Guide](getting_started.md)
- [Streaming Guide](streaming.md)
- [Distributed Systems Guide](distributed_systems.md)
- [Error Handling Guide](error_handling.md)
