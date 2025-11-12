defmodule ObjectStoreX.GetOptions do
  @moduledoc """
  Options for conditional GET operations.

  Supports HTTP-style conditional requests for caching and consistency.
  All conditions are optional and can be combined.

  ## Fields

  * `:if_match` - Only return if ETag matches (HTTP If-Match header)
  * `:if_none_match` - Only return if ETag differs (HTTP If-None-Match header)
  * `:if_modified_since` - Only return if modified after date (Unix timestamp)
  * `:if_unmodified_since` - Only return if not modified since date (Unix timestamp)
  * `:range` - Byte range to fetch (see `ObjectStoreX.Range`)
  * `:version` - Specific object version (provider-specific)
  * `:head` - Return metadata only, no content (boolean)

  ## Examples

      # HTTP cache validation
      cached_etag = "abc123"
      options = %ObjectStoreX.GetOptions{
        if_none_match: cached_etag
      }

      # Consistent read with ETag
      options = %ObjectStoreX.GetOptions{
        if_match: expected_etag
      }

      # Range read with conditions
      options = %ObjectStoreX.GetOptions{
        range: %ObjectStoreX.Range{start: 0, end: 1000},
        if_unmodified_since: ~U[2025-01-01 00:00:00Z] |> DateTime.to_unix()
      }

      # Head-only request (metadata without content)
      options = %ObjectStoreX.GetOptions{
        head: true
      }
  """

  @type t :: %__MODULE__{
          if_match: String.t() | nil,
          if_none_match: String.t() | nil,
          if_modified_since: integer() | nil,
          if_unmodified_since: integer() | nil,
          range: ObjectStoreX.Range.t() | nil,
          version: String.t() | nil,
          head: boolean()
        }

  defstruct [
    :if_match,
    :if_none_match,
    :if_modified_since,
    :if_unmodified_since,
    :range,
    :version,
    head: false
  ]

  @doc """
  Create a default GetOptions struct with no conditions set.

  ## Examples

      iex> ObjectStoreX.GetOptions.new()
      %ObjectStoreX.GetOptions{
        if_match: nil,
        if_none_match: nil,
        if_modified_since: nil,
        if_unmodified_since: nil,
        range: nil,
        version: nil,
        head: false
      }
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Create a GetOptions struct from a keyword list.

  ## Examples

      iex> ObjectStoreX.GetOptions.from_keyword(if_match: "abc123", head: true)
      %ObjectStoreX.GetOptions{
        if_match: "abc123",
        head: true
      }
  """
  @spec from_keyword(keyword()) :: t()
  def from_keyword(opts) do
    struct(__MODULE__, opts)
  end
end
