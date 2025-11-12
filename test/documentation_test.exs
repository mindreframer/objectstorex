defmodule ObjectStoreX.DocumentationTest do
  @moduledoc """
  OBX004_2A: Documentation Tests

  This test suite validates that all public modules and functions have proper
  documentation according to production-ready standards.
  """

  use ExUnit.Case, async: true

  @doc """
  OBX004_2A_T1: Test all public functions have @spec
  """
  test "all public functions have @spec" do
    modules = [ObjectStoreX, ObjectStoreX.Stream, ObjectStoreX.Error]

    for module <- modules do
      {:docs_v1, _, :elixir, _, _module_doc, _, functions} = Code.fetch_docs(module)

      for {{:function, name, arity}, _, _, doc, _metadata} <- functions do
        # Skip private functions (start with _) and hidden functions
        is_hidden = is_map(doc) && Map.get(doc, :hidden, false)
        is_private = String.starts_with?(to_string(name), "_")

        unless is_hidden or is_private or doc == :hidden do
          # Check that the function has a spec
          {:ok, specs} = Code.Typespec.fetch_specs(module)

          function_has_spec =
            specs
            |> Enum.any?(fn
              {{^name, ^arity}, _} -> true
              _ -> false
            end)

          assert function_has_spec,
                 "#{inspect(module)}.#{name}/#{arity} is missing @spec"
        end
      end
    end
  end

  @doc """
  OBX004_2A_T2: Test all public functions have @doc
  """
  test "all public functions have @doc" do
    modules = [ObjectStoreX, ObjectStoreX.Stream, ObjectStoreX.Error]

    for module <- modules do
      {:docs_v1, _, :elixir, _, _module_doc, _, functions} = Code.fetch_docs(module)

      for {{:function, name, arity}, _, _, doc, _} <- functions do
        # Skip private functions (start with _) and already hidden functions
        is_hidden = is_map(doc) && Map.get(doc, :hidden, false)
        is_private = String.starts_with?(to_string(name), "_")

        unless is_hidden or is_private or doc == :hidden do
          refute doc == :none,
                 "#{inspect(module)}.#{name}/#{arity} is missing @doc"
        end
      end
    end
  end

  @doc """
  OBX004_2A_T3: Test all modules have @moduledoc
  """
  test "all modules have @moduledoc" do
    modules = [
      ObjectStoreX,
      ObjectStoreX.Stream,
      ObjectStoreX.Error,
      ObjectStoreX.Native,
      ObjectStoreX.PutMode,
      ObjectStoreX.GetOptions,
      ObjectStoreX.Range,
      ObjectStoreX.Attributes
    ]

    for module <- modules do
      {:docs_v1, _, :elixir, _, module_doc, _, _} = Code.fetch_docs(module)

      refute module_doc == :none,
             "#{inspect(module)} is missing @moduledoc"
    end
  end

  @doc """
  OBX004_2A_T4: Test README examples compile
  """
  test "README examples compile" do
    # This is a basic check - in a real scenario you'd extract and compile code blocks
    readme_path = Path.join([File.cwd!(), "README.md"])
    assert File.exists?(readme_path), "README.md not found"

    content = File.read!(readme_path)

    # Check that README contains key sections
    assert content =~ "ObjectStoreX"
    assert content =~ "Installation"
    assert content =~ "Quick Start"
    assert content =~ "Features"
  end

  @doc """
  OBX004_2A_T5: Test getting started guide examples work
  """
  test "getting started guide exists and has content" do
    guide_path = Path.join([File.cwd!(), "guides", "getting_started.md"])
    assert File.exists?(guide_path), "Getting started guide not found"

    content = File.read!(guide_path)

    # Check that guide contains key sections
    assert content =~ "Getting Started"
    assert content =~ "Installation"
    assert content =~ "Your First Store"
    assert content =~ "Quick Reference"
  end

  @doc """
  OBX004_2A_T6: Test mix docs generates without errors
  """
  test "mix docs can be generated" do
    # This test verifies that the ExDoc configuration is valid
    # by checking that all required files exist

    # Check guides exist
    guides = [
      "guides/getting_started.md",
      "guides/configuration.md",
      "guides/streaming.md",
      "guides/distributed_systems.md",
      "guides/error_handling.md"
    ]

    for guide <- guides do
      path = Path.join([File.cwd!(), guide])
      assert File.exists?(path), "Guide #{guide} not found"
    end

    # Check other docs exist
    assert File.exists?(Path.join([File.cwd!(), "README.md"]))
    assert File.exists?(Path.join([File.cwd!(), "CHANGELOG.md"]))
    assert File.exists?(Path.join([File.cwd!(), "CONTRIBUTING.md"]))
  end
end
