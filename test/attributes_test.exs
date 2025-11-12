defmodule ObjectStoreX.AttributesTest do
  use ExUnit.Case, async: true

  alias ObjectStoreX

  setup do
    # Create an in-memory store for testing
    {:ok, store} = ObjectStoreX.new(:memory)
    %{store: store}
  end

  describe "OBX003_3A: Attributes & Metadata" do
    test "OBX003_3A_T1: Test put with content_type attribute accepts input", %{store: store} do
      data = ~s({"key": "value"})
      path = "test.json"

      # Put with content_type - should succeed
      assert {:ok, _meta} =
               ObjectStoreX.put(store, path, data, content_type: "application/json")

      # Verify object was created
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert meta[:location] == path
      assert meta[:size] == byte_size(data)
    end

    test "OBX003_3A_T2: Test put with cache_control attribute accepts input", %{store: store} do
      data = "cached content"
      path = "cached.txt"

      # Put with cache_control - should succeed
      assert {:ok, _meta} =
               ObjectStoreX.put(store, path, data, cache_control: "max-age=3600")

      # Verify object was created
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert meta[:location] == path
    end

    test "OBX003_3A_T3: Test put with content_disposition accepts input", %{store: store} do
      data = "file content"
      path = "download.txt"

      # Put with content_disposition - should succeed
      assert {:ok, _meta} =
               ObjectStoreX.put(store, path, data,
                 content_disposition: "attachment; filename=download.txt"
               )

      # Verify object was created
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert meta[:location] == path
    end

    test "OBX003_3A_T4: Test head returns basic metadata", %{store: store} do
      data = "test data"
      path = "test.xml"

      # Put with content_type
      assert {:ok, _} = ObjectStoreX.put(store, path, data, content_type: "application/xml")

      # Head should return basic metadata
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert is_map(meta)
      assert meta[:location] == path
      assert meta[:size] == byte_size(data)
      assert is_binary(meta[:last_modified])
    end

    test "OBX003_3A_T5: Test put with multiple content attributes", %{store: store} do
      data = "test data with metadata"
      path = "test_meta.txt"

      # Put with content attributes - should not raise errors
      assert {:ok, _meta} =
               ObjectStoreX.put(store, path, data,
                 content_type: "text/plain",
                 content_encoding: "utf-8"
               )

      # Verify object was created successfully
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert meta[:size] == byte_size(data)
    end

    test "OBX003_3A_T6: Test put with tags accepts input without error", %{store: store} do
      data = "tagged data"
      path = "tagged.txt"

      # Put with tags - should succeed even if provider doesn't support tags
      result =
        ObjectStoreX.put(store, path, data,
          tags: %{"environment" => "test", "version" => "1.0"}
        )

      # Should succeed (tags may be ignored on unsupported providers)
      assert match?({:ok, _}, result)

      # Verify object was created
      assert {:ok, _} = ObjectStoreX.get(store, path)
    end

    test "OBX003_3A_T7: Test multiple attributes together", %{store: store} do
      data = "multi-attribute data"
      path = "multi.pdf"

      # Put with multiple attributes - should not raise errors
      assert {:ok, _meta} =
               ObjectStoreX.put(store, path, data,
                 content_type: "application/pdf",
                 content_disposition: "attachment; filename=report.pdf",
                 cache_control: "no-cache",
                 content_language: "en-US"
               )

      # Verify object was created successfully
      assert {:ok, meta} = ObjectStoreX.head(store, path)
      assert meta[:size] == byte_size(data)
    end

    test "OBX003_3A_T8: Test attributes with mode options work together", %{store: store} do
      data = "roundtrip data"
      path = "roundtrip.html"

      # Put with both attributes and mode - should work
      assert {:ok, put_meta} =
               ObjectStoreX.put(store, path, data,
                 mode: :create,
                 content_type: "text/html",
                 cache_control: "public, max-age=86400"
               )

      # Verify etag is returned
      assert is_binary(put_meta.etag) or put_meta.etag == ""

      # Verify object exists
      assert {:ok, head_meta} = ObjectStoreX.head(store, path)
      assert head_meta[:location] == path

      # Get should work
      assert {:ok, retrieved_data} = ObjectStoreX.get(store, path)
      assert retrieved_data == data

      # Try to create again - should fail with :already_exists
      assert {:error, :already_exists} =
               ObjectStoreX.put(store, path, "new data", mode: :create)
    end
  end
end
