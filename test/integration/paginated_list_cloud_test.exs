defmodule ObjectStoreX.PaginatedListCloudTest do
  use ExUnit.Case, async: false

  @moduletag :cloud

  @required_environment ~w(AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY TEST_S3_BUCKET)
  @credentials_available Enum.all?(@required_environment, &(System.get_env(&1) not in [nil, ""]))

  unless @credentials_available do
    @moduletag skip: "set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and TEST_S3_BUCKET to run"
  end

  test "S3-compatible native pages traverse mixed immediate entries exactly once" do
    {:ok, store} =
      ObjectStoreX.new(:s3,
        bucket: System.fetch_env!("TEST_S3_BUCKET"),
        region: System.get_env("TEST_S3_REGION", System.get_env("AWS_REGION", "us-east-1")),
        access_key_id: System.fetch_env!("AWS_ACCESS_KEY_ID"),
        secret_access_key: System.fetch_env!("AWS_SECRET_ACCESS_KEY"),
        endpoint: optional_env("TEST_S3_ENDPOINT")
      )

    prefix =
      "objectstorex-tests/paginated-list/#{System.system_time(:microsecond)}-#{System.unique_integer([:positive])}/"

    paths = [
      prefix <> "alpha.txt",
      prefix <> "beta/one.txt",
      prefix <> "delta.txt",
      prefix <> "gamma/deep/two.txt"
    ]

    on_exit(fn -> Enum.each(paths, &ObjectStoreX.delete(store, &1)) end)

    for path <- paths do
      assert :ok = ObjectStoreX.put(store, path, "page-test")
    end

    pages = collect_pages(store, prefix, 2)
    assert length(pages) >= 2
    assert Enum.all?(pages, &(length(&1.objects) + length(&1.prefixes) <= 2))
    assert List.last(pages).next_page_token == nil

    objects =
      pages
      |> Enum.flat_map(& &1.objects)
      |> Enum.map(& &1.location)

    prefixes = Enum.flat_map(pages, & &1.prefixes)

    assert MapSet.new(objects) == MapSet.new([prefix <> "alpha.txt", prefix <> "delta.txt"])

    assert MapSet.new(prefixes) ==
             MapSet.new([
               String.trim_trailing(prefix <> "beta/", "/"),
               String.trim_trailing(prefix <> "gamma/", "/")
             ])

    entries = Enum.map(objects, &{:object, &1}) ++ Enum.map(prefixes, &{:prefix, &1})
    assert length(entries) == length(Enum.uniq(entries))
  end

  defp collect_pages(store, prefix, max_keys, token \\ nil, pages \\ []) do
    assert {:ok, page} =
             ObjectStoreX.list_with_delimiter_page(store,
               prefix: prefix,
               max_keys: max_keys,
               page_token: token
             )

    pages = pages ++ [page]

    case page.next_page_token do
      nil -> pages
      next_token -> collect_pages(store, prefix, max_keys, next_token, pages)
    end
  end

  defp optional_env(name) do
    case System.get_env(name) do
      value when value in [nil, ""] -> nil
      value -> value
    end
  end
end
