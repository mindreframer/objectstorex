defmodule ObjectStoreX.Range do
  @moduledoc """
  Represents a byte range for partial object reads.

  A range specifies a contiguous sequence of bytes to fetch from an object,
  with `start` being inclusive and `end` being exclusive (Rust-style range).

  ## Fields

  * `:start` - Start byte position (inclusive, 0-indexed)
  * `:end` - End byte position (exclusive)

  ## Examples

      # Fetch first 1KB (bytes 0-999)
      %ObjectStoreX.Range{start: 0, end: 1000}

      # Fetch bytes 100-199
      %ObjectStoreX.Range{start: 100, end: 200}

      # Fetch 1MB starting at 1MB offset
      %ObjectStoreX.Range{start: 1_048_576, end: 2_097_152}

  ## Notes

  The range follows Rust-style half-open intervals `[start, end)`:
  - `start` is inclusive
  - `end` is exclusive
  - The number of bytes fetched is `end - start`
  """

  @type t :: %__MODULE__{
          start: non_neg_integer(),
          end: non_neg_integer()
        }

  defstruct [:start, :end]

  @doc """
  Create a new Range struct.

  ## Examples

      iex> ObjectStoreX.Range.new(0, 1000)
      %ObjectStoreX.Range{start: 0, end: 1000}
  """
  @spec new(non_neg_integer(), non_neg_integer()) :: t()
  def new(start, end_pos) when start >= 0 and end_pos > start do
    %__MODULE__{start: start, end: end_pos}
  end

  @doc """
  Calculate the size (number of bytes) in the range.

  ## Examples

      iex> range = ObjectStoreX.Range.new(0, 1000)
      iex> ObjectStoreX.Range.size(range)
      1000

      iex> range = ObjectStoreX.Range.new(100, 200)
      iex> ObjectStoreX.Range.size(range)
      100
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{start: start, end: end_pos}) do
    end_pos - start
  end
end
