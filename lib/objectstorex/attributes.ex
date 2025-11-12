defmodule ObjectStoreX.Attributes do
  @moduledoc """
  Represents object attributes for setting HTTP headers and metadata.

  ## Fields

  - `content_type` - MIME type (e.g., "application/json")
  - `content_encoding` - Encoding (e.g., "gzip")
  - `content_disposition` - Download behavior (e.g., "attachment; filename=file.pdf")
  - `cache_control` - Cache directives (e.g., "max-age=3600")
  - `content_language` - Language code (e.g., "en-US")

  ## Examples

      # Create attributes for JSON data
      %ObjectStoreX.Attributes{
        content_type: "application/json",
        cache_control: "max-age=3600"
      }

      # Create attributes for file download
      %ObjectStoreX.Attributes{
        content_type: "application/pdf",
        content_disposition: "attachment; filename=report.pdf"
      }
  """

  @type t :: %__MODULE__{
          content_type: String.t() | nil,
          content_encoding: String.t() | nil,
          content_disposition: String.t() | nil,
          cache_control: String.t() | nil,
          content_language: String.t() | nil
        }

  defstruct [
    :content_type,
    :content_encoding,
    :content_disposition,
    :cache_control,
    :content_language
  ]
end
