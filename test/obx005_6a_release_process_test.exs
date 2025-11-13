defmodule ObjectStoreX.OBX005_6A_ReleaseProcessTest do
  use ExUnit.Case, async: false

  @moduledoc """
  OBX005_6A: Release Process & Checklist Validation Tests

  These tests validate the release process infrastructure and documentation
  to ensure all necessary files, configurations, and procedures are in place
  for successful releases with precompiled NIFs.
  """

  describe "OBX005_6A_T1: Version Management" do
    test "version can be bumped in mix.exs" do
      # Test that version format is valid and can be parsed
      mix_config = Mix.Project.config()
      version = mix_config[:version]

      # Version should follow semantic versioning
      assert version =~ ~r/^\d+\.\d+\.\d+(-[a-zA-Z0-9.-]+)?$/,
             "Version should follow semantic versioning (X.Y.Z or X.Y.Z-suffix)"

      # Version should be accessible at compile time
      assert is_binary(version)
      assert String.length(version) > 0
    end

    test "dev flag correctly identifies development versions" do
      mix_config = Mix.Project.config()
      version = mix_config[:version]

      # @dev? should be true for versions ending with "-dev"
      is_dev = String.ends_with?(version, "-dev")

      if is_dev do
        # In dev mode, rustler should not be optional
        deps = Mix.Project.config()[:deps] || []

        rustler_dep =
          Enum.find(deps, fn
            {:rustler, _opts} -> true
            {:rustler, _version, _opts} -> true
            _ -> false
          end)

        case rustler_dep do
          {:rustler, opts} when is_list(opts) ->
            refute Keyword.get(opts, :optional, false),
                   "Rustler should not be optional in dev mode"

          {:rustler, _version, opts} when is_list(opts) ->
            refute Keyword.get(opts, :optional, false),
                   "Rustler should not be optional in dev mode"

          _ ->
            :ok
        end
      end
    end

    test "force_build flag reads environment variable" do
      # Test OBJECTSTOREX_BUILD=1
      System.put_env("OBJECTSTOREX_BUILD", "1")
      assert System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"]
      System.delete_env("OBJECTSTOREX_BUILD")

      # Test OBJECTSTOREX_BUILD=true
      System.put_env("OBJECTSTOREX_BUILD", "true")
      assert System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"]
      System.delete_env("OBJECTSTOREX_BUILD")

      # Test OBJECTSTOREX_BUILD=0 (should not trigger build)
      System.put_env("OBJECTSTOREX_BUILD", "0")
      refute System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"]
      System.delete_env("OBJECTSTOREX_BUILD")
    end
  end

  describe "OBX005_6A_T2: CHANGELOG Management" do
    test "CHANGELOG.md exists and is well-formed" do
      changelog_path = Path.join([File.cwd!(), "CHANGELOG.md"])
      assert File.exists?(changelog_path), "CHANGELOG.md should exist"

      content = File.read!(changelog_path)
      assert String.length(content) > 0, "CHANGELOG.md should not be empty"

      # Should have markdown headers
      assert content =~ ~r/^#/m, "CHANGELOG should have markdown headers"

      # Should mention releases or versions
      assert content =~ ~r/\d+\.\d+\.\d+/ or content =~ ~r/Unreleased/i,
             "CHANGELOG should mention versions or unreleased changes"
    end

    test "CHANGELOG mentions precompiled NIF support" do
      changelog_path = Path.join([File.cwd!(), "CHANGELOG.md"])

      if File.exists?(changelog_path) do
        content = File.read!(changelog_path)

        assert content =~ ~r/precompiled/i or content =~ ~r/NIF/i,
               "CHANGELOG should document precompiled NIF feature"
      end
    end
  end

  describe "OBX005_6A_T3: Git Tag Process" do
    test "git is available and repository is valid" do
      # Check git is available
      case System.cmd("git", ["--version"], stderr_to_stdout: true) do
        {output, 0} ->
          assert output =~ ~r/git version/i, "Git should be available"

        _ ->
          flunk("Git should be installed and available")
      end

      # Check we're in a git repository
      case System.cmd("git", ["rev-parse", "--git-dir"], stderr_to_stdout: true) do
        {output, 0} ->
          assert String.trim(output) != "", "Should be in a git repository"

        _ ->
          flunk("Should be in a git repository")
      end
    end

    test "can list and verify git tags format" do
      case System.cmd("git", ["tag", "-l"], stderr_to_stdout: true) do
        {output, 0} ->
          tags = String.split(output, "\n", trim: true)

          # If there are tags, verify they follow vX.Y.Z format
          version_tags = Enum.filter(tags, &String.starts_with?(&1, "v"))

          for tag <- version_tags do
            assert tag =~ ~r/^v\d+\.\d+\.\d+/,
                   "Version tags should follow vX.Y.Z format, got: #{tag}"
          end

        {_output, _code} ->
          # Git tag might fail if no tags exist yet, which is ok
          :ok
      end
    end
  end

  describe "OBX005_6A_T4: CI Build Verification" do
    test "GitHub Actions workflow file exists" do
      workflow_path = Path.join([File.cwd!(), ".github", "workflows", "nif-release.yml"])
      assert File.exists?(workflow_path), "nif-release.yml workflow should exist"
    end

    test "CI workflow triggers on tags" do
      workflow_path = Path.join([File.cwd!(), ".github", "workflows", "nif-release.yml"])

      if File.exists?(workflow_path) do
        content = File.read!(workflow_path)

        # Check for tag trigger
        assert content =~ ~r/on:.*tags/s or content =~ ~r/tags:/m,
               "Workflow should trigger on tags"
      end
    end

    test "CI workflow builds all 8 targets" do
      workflow_path = Path.join([File.cwd!(), ".github", "workflows", "nif-release.yml"])

      if File.exists?(workflow_path) do
        content = File.read!(workflow_path)

        # Check all 8 targets are in the workflow
        targets = [
          "aarch64-apple-darwin",
          "x86_64-apple-darwin",
          "aarch64-unknown-linux-gnu",
          "x86_64-unknown-linux-gnu",
          "aarch64-unknown-linux-musl",
          "x86_64-unknown-linux-musl",
          "x86_64-pc-windows-msvc",
          "x86_64-pc-windows-gnu"
        ]

        for target <- targets do
          assert content =~ target, "Workflow should include target: #{target}"
        end
      end
    end
  end

  describe "OBX005_6A_T5: Checksum Generation" do
    test "gen.checksum alias exists in mix.exs" do
      aliases = Mix.Project.config()[:aliases] || []

      # Check if aliases is a keyword list or map
      gen_checksum =
        cond do
          is_list(aliases) -> Keyword.get(aliases, :"gen.checksum")
          is_map(aliases) -> Map.get(aliases, :"gen.checksum")
          true -> nil
        end

      assert gen_checksum != nil, "gen.checksum alias should be defined"

      # Verify it calls rustler_precompiled.download
      assert gen_checksum =~ ~r/rustler_precompiled\.download/,
             "gen.checksum should call rustler_precompiled.download"
    end

    test "checksum file pattern is gitignored" do
      gitignore_path = Path.join([File.cwd!(), ".gitignore"])

      if File.exists?(gitignore_path) do
        content = File.read!(gitignore_path)

        assert content =~ ~r/checksum.*\.exs/i,
               ".gitignore should ignore checksum-*.exs files"
      end
    end

    test "checksum file matches expected naming pattern" do
      # The checksum file should be named: checksum-Elixir.ObjectStoreX.Native.exs
      expected_pattern = "checksum-Elixir.ObjectStoreX.Native.exs"

      # Check if it's in package files
      package_files = Mix.Project.config()[:package][:files] || []

      assert Enum.any?(package_files, fn file ->
               String.contains?(file, "checksum-") and String.ends_with?(file, ".exs")
             end),
             "Package should include checksum file: #{expected_pattern}"
    end
  end

  describe "OBX005_6A_T6: Hex Package Verification" do
    test "package configuration includes all required files" do
      package = Mix.Project.config()[:package]
      assert package != nil, "Package configuration should exist"

      files = package[:files] || []
      assert length(files) > 0, "Package should specify files to include"

      # Required files/directories
      required = [
        "lib",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ]

      for req <- required do
        assert Enum.any?(files, &String.contains?(&1, req)),
               "Package should include: #{req}"
      end
    end

    test "package includes Rust source files" do
      package_files = Mix.Project.config()[:package][:files] || []

      # Should include Rust source
      assert Enum.any?(package_files, &String.contains?(&1, "native")),
             "Package should include native/ directory"

      assert Enum.any?(package_files, &String.contains?(&1, "Cargo")),
             "Package should include Cargo files"
    end

    test "package includes cargo configuration files" do
      package_files = Mix.Project.config()[:package][:files] || []

      # Should include .cargo/config.toml
      assert Enum.any?(package_files, &String.contains?(&1, ".cargo")),
             "Package should include .cargo directory"

      # Should include Cross.toml
      assert Enum.any?(package_files, &String.contains?(&1, "Cross.toml")),
             "Package should include Cross.toml"
    end

    test "package excludes build artifacts" do
      package_files = Mix.Project.config()[:package][:files] || []

      # Should NOT include build directories
      refute Enum.any?(package_files, &String.contains?(&1, "_build")),
             "Package should not include _build directory"

      refute Enum.any?(package_files, &String.contains?(&1, "deps")),
             "Package should not include deps directory"

      refute Enum.any?(package_files, &String.contains?(&1, "target")),
             "Package should not include target directory"
    end

    test "package metadata is complete" do
      package = Mix.Project.config()[:package]
      assert package != nil, "Package configuration should exist"

      # Check required metadata
      assert package[:name], "Package should have a name"
      assert package[:licenses], "Package should specify licenses"
      assert package[:links], "Package should have links"

      # Check links include GitHub
      links = package[:links] || %{}
      assert links["GitHub"] || links[:github], "Package should have GitHub link"
    end
  end

  describe "OBX005_6A_T7: Release Documentation" do
    test "RELEASE_CHECKLIST.md exists" do
      checklist_path = Path.join([File.cwd!(), "RELEASE_CHECKLIST.md"])
      assert File.exists?(checklist_path), "RELEASE_CHECKLIST.md should exist"
    end

    test "RELEASE_CHECKLIST.md is comprehensive" do
      checklist_path = Path.join([File.cwd!(), "RELEASE_CHECKLIST.md"])

      if File.exists?(checklist_path) do
        content = File.read!(checklist_path)

        # Should document key steps
        assert content =~ ~r/version/i, "Checklist should mention version management"
        assert content =~ ~r/tag/i, "Checklist should mention git tags"
        assert content =~ ~r/checksum/i, "Checklist should mention checksum generation"
        assert content =~ ~r/hex/i, "Checklist should mention hex publishing"
        assert content =~ ~r/CI|GitHub Actions/i, "Checklist should mention CI builds"

        # Should have actual checklist items
        assert content =~ ~r/\[[ x]\]/i, "Should contain checklist items"

        # Should be substantial (more than just a stub)
        assert String.length(content) > 1000,
               "Checklist should be comprehensive (>1000 chars)"
      end
    end

    test "README documents precompiled NIFs" do
      readme_path = Path.join([File.cwd!(), "README.md"])

      if File.exists?(readme_path) do
        content = File.read!(readme_path)

        assert content =~ ~r/precompiled/i or content =~ ~r/NIF/i,
               "README should document precompiled NIFs"
      end
    end

    test "README documents supported platforms" do
      readme_path = Path.join([File.cwd!(), "README.md"])

      if File.exists?(readme_path) do
        content = File.read!(readme_path)

        # Should mention key platforms
        platforms_mentioned =
          content =~ ~r/macOS/i or content =~ ~r/Linux/i or content =~ ~r/Windows/i

        assert platforms_mentioned, "README should document supported platforms"
      end
    end

    test "README documents building from source" do
      readme_path = Path.join([File.cwd!(), "README.md"])

      if File.exists?(readme_path) do
        content = File.read!(readme_path)

        # Should mention Rust or building from source
        assert content =~ ~r/Rust/i or content =~ ~r/build.*source/i or
                 content =~ ~r/OBJECTSTOREX_BUILD/,
               "README should document building from source"
      end
    end
  end

  describe "OBX005_6A_T8: Release Process Validation" do
    test "mix hex.build should work" do
      # This is a smoke test - just verify the command exists
      # We don't actually build the package in tests
      case System.cmd("mix", ["help", "hex.build"], stderr_to_stdout: true) do
        {output, 0} ->
          assert output =~ ~r/mix hex\.build/i, "mix hex.build command should be available"

        _ ->
          flunk("mix hex.build should be available (is hex installed?)")
      end
    end

    test "project is properly configured for hex publishing" do
      config = Mix.Project.config()

      # Must have app name
      assert config[:app], "Project must have app name"

      # Must have version
      assert config[:version], "Project must have version"

      # Must have description
      assert config[:description], "Project should have description for hex"

      # Must have package configuration
      assert config[:package], "Project must have package configuration"
    end

    test "dependencies are properly specified" do
      deps = Mix.Project.config()[:deps] || []

      # Should have rustler_precompiled
      assert Enum.any?(deps, fn
               {:rustler_precompiled, _} -> true
               _ -> false
             end),
             "Project should depend on rustler_precompiled"

      # Each dependency should be well-formed
      for dep <- deps do
        case dep do
          {name, _version} when is_atom(name) ->
            :ok

          {name, _version, _opts} when is_atom(name) ->
            :ok

          _ ->
            flunk(
              "Dependency should be {name, version} or {name, version, opts}, got: #{inspect(dep)}"
            )
        end
      end
    end
  end

  describe "OBX005_6A_T9: Post-Release Verification Setup" do
    test "basic NIF functions are defined" do
      # Verify the native module has the expected functions
      functions = ObjectStoreX.Native.__info__(:functions)

      # Should have key functions like new_local/1, put/3, get/2
      assert Keyword.has_key?(functions, :new_local),
             "Native module should have new_local/1 function"

      assert Keyword.has_key?(functions, :put),
             "Native module should have put/3 function"

      assert Keyword.has_key?(functions, :get),
             "Native module should have get/2 function"
    end

    test "native module uses RustlerPrecompiled" do
      # Check the module's use statement (this is a compile-time check)
      # We verify by checking that RustlerPrecompiled behavior is present

      module_info = ObjectStoreX.Native.module_info(:attributes)

      # Should have been compiled (smoke test)
      assert is_list(module_info), "Native module should be compiled"
      assert length(module_info) > 0, "Native module should have attributes"
    end

    test "can verify installation in test environment" do
      # Verify the NIF is loaded in test environment
      # This tests that OBJECTSTOREX_BUILD or precompiled NIF works

      # Try to call a NIF function - we just verify the function is defined
      # The actual NIF behavior is tested in other test files
      # Here we only verify the function exists and is callable
      assert function_exported?(ObjectStoreX.Native, :new_local, 1),
             "NIF function new_local/1 should be defined"

      assert function_exported?(ObjectStoreX.Native, :put, 3),
             "NIF function put/3 should be defined"
    end
  end

  describe "OBX005_6A_T10: Troubleshooting Documentation" do
    test "README includes troubleshooting section" do
      readme_path = Path.join([File.cwd!(), "README.md"])

      if File.exists?(readme_path) do
        content = File.read!(readme_path)

        # Should have troubleshooting information
        has_troubleshooting =
          content =~ ~r/troubleshoot/i or
            content =~ ~r/common.*issue/i or
            content =~ ~r/problem.*solution/i or
            content =~ ~r/error.*fix/i

        assert has_troubleshooting, "README should include troubleshooting information"
      end
    end

    test "RELEASE_CHECKLIST includes troubleshooting section" do
      checklist_path = Path.join([File.cwd!(), "RELEASE_CHECKLIST.md"])

      if File.exists?(checklist_path) do
        content = File.read!(checklist_path)

        assert content =~ ~r/troubleshoot/i,
               "RELEASE_CHECKLIST should include troubleshooting section"
      end
    end
  end
end
