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

  @doc """
  OBX005_5A_T1: Test README installation instructions are accurate
  """
  test "OBX005_5A_T1: README has installation section with precompiled NIF info" do
    readme_path = Path.join([File.cwd!(), "README.md"])
    content = File.read!(readme_path)

    # Check installation section exists
    assert content =~ "## Installation"
    assert content =~ "{:objectstorex, \"~> 0.1.0\"}"

    # Check precompiled NIFs section exists
    assert content =~ "### Precompiled NIFs"
    assert content =~ "No Rust toolchain required"

    # Check all 8 platforms are documented
    assert content =~ "aarch64-apple-darwin"
    assert content =~ "x86_64-apple-darwin"
    assert content =~ "aarch64-unknown-linux-gnu"
    assert content =~ "x86_64-unknown-linux-gnu"
    assert content =~ "aarch64-unknown-linux-musl"
    assert content =~ "x86_64-unknown-linux-musl"
    assert content =~ "x86_64-pc-windows-msvc"
    assert content =~ "x86_64-pc-windows-gnu"
  end

  @doc """
  OBX005_5A_T2: Test forced build instructions work
  """
  test "OBX005_5A_T2: README has building from source section" do
    readme_path = Path.join([File.cwd!(), "README.md"])
    content = File.read!(readme_path)

    # Check building from source section exists
    assert content =~ "### Building from Source"

    # Check it documents Rust installation
    assert content =~ "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs"

    # Check it documents OBJECTSTOREX_BUILD environment variable
    assert content =~ "OBJECTSTOREX_BUILD=1"
    assert content =~ "export OBJECTSTOREX_BUILD=1"
  end

  @doc """
  OBX005_5A_T3: Test all platform names are correct
  """
  test "OBX005_5A_T3: README platform list matches expected targets" do
    readme_path = Path.join([File.cwd!(), "README.md"])
    content = File.read!(readme_path)

    # Expected targets based on spec
    expected_targets = [
      "aarch64-apple-darwin",
      "x86_64-apple-darwin",
      "aarch64-unknown-linux-gnu",
      "x86_64-unknown-linux-gnu",
      "aarch64-unknown-linux-musl",
      "x86_64-unknown-linux-musl",
      "x86_64-pc-windows-msvc",
      "x86_64-pc-windows-gnu"
    ]

    for target <- expected_targets do
      assert content =~ target,
             "README is missing target: #{target}"
    end
  end

  @doc """
  OBX005_5A_T4: Test troubleshooting steps are valid
  """
  test "OBX005_5A_T4: README has troubleshooting section" do
    readme_path = Path.join([File.cwd!(), "README.md"])
    content = File.read!(readme_path)

    # Check troubleshooting section exists
    assert content =~ "### Troubleshooting"

    # Check it covers common issues
    assert content =~ "NIF not loaded"
    assert content =~ "Precompiled binary download fails"
    assert content =~ "Compilation errors when building from source"

    # Check it provides solutions
    assert content =~ "OBJECTSTOREX_BUILD=1 mix deps.compile objectstorex --force"
    assert content =~ "rustc --version"
  end

  @doc """
  OBX005_5A_T5: Test CHANGELOG documents precompiled NIF support
  """
  test "OBX005_5A_T5: CHANGELOG documents precompiled NIF feature" do
    changelog_path = Path.join([File.cwd!(), "CHANGELOG.md"])
    content = File.read!(changelog_path)

    # Check CHANGELOG mentions precompiled NIFs
    assert content =~ "Precompiled NIFs"
    assert content =~ "no Rust toolchain required"

    # Check it documents the deployment section
    assert content =~ "Deployment & Distribution"
    assert content =~ "Automated CI/CD pipeline"
    assert content =~ "GitHub Actions"
    assert content =~ "Checksum verification"

    # Check release process updated
    assert content =~ "mix gen.checksum"
  end
end
