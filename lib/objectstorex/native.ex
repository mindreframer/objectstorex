defmodule ObjectStoreX.Native do
  @moduledoc false
  # NIF module - functions are implemented in Rust

  mix_config = Mix.Project.config()
  version = mix_config[:version]
  github_url = mix_config[:package][:links]["GitHub"]
  mode = if Mix.env() in [:dev, :test], do: :debug, else: :release

  use RustlerPrecompiled,
    otp_app: :objectstorex,
    crate: "objectstorex",
    version: version,
    base_url: "#{github_url}/releases/download/v#{version}",
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      aarch64-unknown-linux-gnu
      x86_64-unknown-linux-gnu
      aarch64-unknown-linux-musl
      x86_64-unknown-linux-musl
      x86_64-pc-windows-msvc
      x86_64-pc-windows-gnu
    ),
    nif_versions: ["2.15"],
    mode: mode,
    force_build: System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"]

  # Provider builders
  def new_s3(_bucket, _region, _access_key_id, _secret_access_key, _endpoint),
    do: :erlang.nif_error(:nif_not_loaded)

  def new_azure(_account, _container, _access_key), do: :erlang.nif_error(:nif_not_loaded)
  def new_gcs(_bucket, _service_account_key), do: :erlang.nif_error(:nif_not_loaded)
  def new_local(_path), do: :erlang.nif_error(:nif_not_loaded)
  def new_memory, do: :erlang.nif_error(:nif_not_loaded)

  # Operations
  def put(_store, _path, _data), do: :erlang.nif_error(:nif_not_loaded)
  def put_with_mode(_store, _path, _data, _mode), do: :erlang.nif_error(:nif_not_loaded)

  def put_with_attributes(_store, _path, _data, _mode, _attributes, _tags),
    do: :erlang.nif_error(:nif_not_loaded)

  def get(_store, _path), do: :erlang.nif_error(:nif_not_loaded)
  def get_with_options(_store, _path, _options), do: :erlang.nif_error(:nif_not_loaded)
  def delete(_store, _path), do: :erlang.nif_error(:nif_not_loaded)
  def head(_store, _path), do: :erlang.nif_error(:nif_not_loaded)
  def copy(_store, _from, _to), do: :erlang.nif_error(:nif_not_loaded)
  def rename(_store, _from, _to), do: :erlang.nif_error(:nif_not_loaded)
  def copy_if_not_exists(_store, _from, _to), do: :erlang.nif_error(:nif_not_loaded)
  def rename_if_not_exists(_store, _from, _to), do: :erlang.nif_error(:nif_not_loaded)
  def get_ranges(_store, _path, _ranges), do: :erlang.nif_error(:nif_not_loaded)
  def delete_many(_store, _paths), do: :erlang.nif_error(:nif_not_loaded)

  # Streaming operations
  def start_download_stream(_store, _path, _receiver_pid), do: :erlang.nif_error(:nif_not_loaded)
  def cancel_download_stream(_stream_id), do: :erlang.nif_error(:nif_not_loaded)

  # Upload streaming (multipart)
  def start_upload_session(_store, _path), do: :erlang.nif_error(:nif_not_loaded)
  def upload_chunk(_session, _chunk), do: :erlang.nif_error(:nif_not_loaded)
  def complete_upload(_session), do: :erlang.nif_error(:nif_not_loaded)
  def abort_upload(_session), do: :erlang.nif_error(:nif_not_loaded)

  # List operations
  def start_list_stream(_store, _prefix, _receiver_pid), do: :erlang.nif_error(:nif_not_loaded)
  def list_with_delimiter(_store, _prefix), do: :erlang.nif_error(:nif_not_loaded)
end
