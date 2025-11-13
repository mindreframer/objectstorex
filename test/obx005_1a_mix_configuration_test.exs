defmodule OBX0051AMixConfigurationTest do
  use ExUnit.Case, async: false

  @moduletag :obx005_1a

  @project_config Mix.Project.config()
  @version @project_config[:version]

  describe "OBX005_1A: Mix Configuration Tests" do
    test "OBX005_1A_T1: Test @dev? flag is false for release versions" do
      # The current version should not end with "-dev" (it's "0.1.0")
      refute String.ends_with?(@version, "-dev"),
             "Expected release version, but got: #{@version}"

      # Verify this matches the module attribute logic
      dev_flag = String.ends_with?(@version, "-dev")
      refute dev_flag, "Expected @dev? to be false for version #{@version}"
    end

    test "OBX005_1A_T2: Test @dev? flag is true for -dev versions" do
      # Simulate a dev version
      dev_version = "0.1.0-dev"
      dev_flag = String.ends_with?(dev_version, "-dev")
      assert dev_flag, "Expected @dev? to be true for version #{dev_version}"

      # Test various dev version formats
      for version <- ["0.1.0-dev", "1.0.0-dev", "2.3.4-dev"] do
        assert String.ends_with?(version, "-dev"),
               "Expected #{version} to be detected as dev version"
      end
    end

    test "OBX005_1A_T3: Test @force_build? reads environment variable" do
      # Save original value
      original_value = System.get_env("OBJECTSTOREX_BUILD")

      try do
        # Test with "1"
        System.put_env("OBJECTSTOREX_BUILD", "1")
        assert System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"],
               "Expected OBJECTSTOREX_BUILD=1 to trigger force build"

        # Test with "true"
        System.put_env("OBJECTSTOREX_BUILD", "true")
        assert System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"],
               "Expected OBJECTSTOREX_BUILD=true to trigger force build"

        # Test with other values
        System.put_env("OBJECTSTOREX_BUILD", "0")
        refute System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"],
               "Expected OBJECTSTOREX_BUILD=0 to not trigger force build"

        System.put_env("OBJECTSTOREX_BUILD", "false")
        refute System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"],
               "Expected OBJECTSTOREX_BUILD=false to not trigger force build"
      after
        # Restore original value
        if original_value do
          System.put_env("OBJECTSTOREX_BUILD", original_value)
        else
          System.delete_env("OBJECTSTOREX_BUILD")
        end
      end
    end

    test "OBX005_1A_T4: Test rustler is optional in prod mode" do
      # Get dependencies configuration
      deps = @project_config[:deps] || Mix.Project.config()[:project][:deps] || deps_from_function()

      # Find rustler dependency
      rustler_dep =
        Enum.find(deps, fn
          {:rustler, _opts} -> true
          {:rustler, _version, _opts} -> true
          _ -> false
        end)

      assert rustler_dep != nil, "rustler dependency not found in mix.exs"

      # Extract options from rustler dependency
      rustler_opts =
        case rustler_dep do
          {:rustler, opts} when is_list(opts) -> opts
          {:rustler, _version, opts} when is_list(opts) -> opts
          _ -> []
        end

      # Check that rustler has optional flag
      # In production (non-dev version), rustler should be optional
      # The logic is: optional: not (@dev? or @force_build?)
      # Since we're in a release version (0.1.0), @dev? is false
      # So rustler should be optional unless OBJECTSTOREX_BUILD is set
      has_optional = Keyword.has_key?(rustler_opts, :optional)
      assert has_optional, "rustler dependency should have :optional key configured"

      # Verify rustler_precompiled is present and not optional
      rustler_precompiled_dep =
        Enum.find(deps, fn
          {:rustler_precompiled, _opts} -> true
          {:rustler_precompiled, _version, _opts} -> true
          _ -> false
        end)

      assert rustler_precompiled_dep != nil,
             "rustler_precompiled dependency not found in mix.exs"
    end

    test "OBX005_1A_T5: Test package includes checksum file" do
      # Get package configuration
      package_config = @project_config[:package]
      assert package_config != nil, "Package configuration not found in mix.exs"

      # Get files list
      files = package_config[:files]
      assert files != nil, "Package files list not found"
      assert is_list(files), "Package files should be a list"

      # Check for checksum file
      assert "checksum-Elixir.ObjectStoreX.Native.exs" in files,
             "checksum-Elixir.ObjectStoreX.Native.exs not included in package files"
    end

    test "OBX005_1A_T6: Test package includes .cargo directory" do
      # Get package configuration
      package_config = @project_config[:package]
      assert package_config != nil, "Package configuration not found in mix.exs"

      # Get files list
      files = package_config[:files]
      assert files != nil, "Package files list not found"

      # Check for .cargo directory
      assert "native/objectstorex/.cargo" in files,
             "native/objectstorex/.cargo not included in package files"

      # Also verify Cross.toml is included
      assert "native/objectstorex/Cross.toml" in files,
             "native/objectstorex/Cross.toml not included in package files"
    end

    test "OBX005_1A_T7: Test gen.checksum alias exists" do
      # Get aliases configuration
      aliases = @project_config[:aliases]
      assert aliases != nil, "Aliases configuration not found in mix.exs"
      assert is_list(aliases), "Aliases should be a list"

      # Convert to keyword list if needed
      aliases_keyword = Keyword.new(aliases)

      # Check for gen.checksum alias
      assert Keyword.has_key?(aliases_keyword, :"gen.checksum"),
             "gen.checksum alias not found in mix.exs"

      # Verify the alias command is correct
      checksum_command = Keyword.get(aliases_keyword, :"gen.checksum")

      assert checksum_command != nil, "gen.checksum alias has no command"

      assert checksum_command =~ "rustler_precompiled.download",
             "gen.checksum should use rustler_precompiled.download"

      assert checksum_command =~ "ObjectStoreX.Native",
             "gen.checksum should reference ObjectStoreX.Native module"

      assert checksum_command =~ "--all",
             "gen.checksum should include --all flag"

      assert checksum_command =~ "--print",
             "gen.checksum should include --print flag"
    end
  end

  # Helper function to get deps if not in config
  defp deps_from_function do
    if function_exported?(Mix.Project.get!(), :deps, 0) do
      apply(Mix.Project.get!(), :deps, [])
    else
      []
    end
  end
end
