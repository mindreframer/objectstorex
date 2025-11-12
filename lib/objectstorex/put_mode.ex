defmodule ObjectStoreX.PutMode do
  @moduledoc """
  Represents the write mode for put operations.

  ## Modes

  - `:overwrite` - Always write, overwriting any existing object (default)
  - `:create` - Only write if the object doesn't exist
  - `{:update, %{etag: ..., version: ...}}` - Only write if the version matches (Compare-And-Swap)

  ## Examples

      # Always overwrite (default)
      ObjectStoreX.put(store, "file.txt", data, mode: :overwrite)

      # Create only (atomic lock)
      ObjectStoreX.put(store, "lock.txt", data, mode: :create)

      # Compare-and-swap with ETag
      {:ok, meta} = ObjectStoreX.head(store, "counter.json")
      ObjectStoreX.put(store, "counter.json", new_data,
        mode: {:update, %{etag: meta[:etag], version: meta[:version]}})
  """

  @type t ::
          :overwrite
          | :create
          | {:update, %{etag: String.t() | nil, version: String.t() | nil}}
end
