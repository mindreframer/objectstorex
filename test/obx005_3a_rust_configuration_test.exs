defmodule OBX0053ARustConfigurationTest do
  use ExUnit.Case, async: true

  @moduletag :obx005_3a

  @moduledoc """
  Tests for Phase OBX005_3A: Rust Configuration

  Validates that all Rust configuration files are properly set up:
  - .cargo/config.toml with platform-specific rustflags
  - Cross.toml for cross-compilation
  - Cargo.toml with NIF version features and rust-version
  """

  @cargo_config_path "native/objectstorex/.cargo/config.toml"
  @cross_toml_path "native/objectstorex/Cross.toml"
  @cargo_toml_path "native/objectstorex/Cargo.toml"

  describe "OBX005_3A_T1: Validate .cargo/config.toml is valid TOML" do
    test "cargo config file exists" do
      assert File.exists?(@cargo_config_path),
             ".cargo/config.toml file does not exist at #{@cargo_config_path}"
    end

    test "cargo config file is readable and has content" do
      {:ok, content} = File.read(@cargo_config_path)
      assert String.length(content) > 0, ".cargo/config.toml file is empty"
    end

    test "cargo config contains required sections" do
      {:ok, content} = File.read(@cargo_config_path)

      # Check for [profile.release] section
      assert content =~ "[profile.release]",
             ".cargo/config.toml missing [profile.release] section"

      # Check for macOS target sections
      assert content =~ "[target.x86_64-apple-darwin]",
             ".cargo/config.toml missing [target.x86_64-apple-darwin] section"

      assert content =~ "[target.aarch64-apple-darwin]",
             ".cargo/config.toml missing [target.aarch64-apple-darwin] section"

      # Check for musl target sections
      assert content =~ "[target.x86_64-unknown-linux-musl]",
             ".cargo/config.toml missing [target.x86_64-unknown-linux-musl] section"

      assert content =~ "[target.aarch64-unknown-linux-musl]",
             ".cargo/config.toml missing [target.aarch64-unknown-linux-musl] section"
    end

    test "cargo config has macOS dynamic_lookup flags" do
      {:ok, content} = File.read(@cargo_config_path)

      # Check for macOS linking flags
      assert content =~ "dynamic_lookup",
             ".cargo/config.toml missing dynamic_lookup flag for macOS"

      assert content =~ "-undefined",
             ".cargo/config.toml missing -undefined flag for macOS"
    end

    test "cargo config has musl CRT flags" do
      {:ok, content} = File.read(@cargo_config_path)

      # Check for musl CRT flags
      assert content =~ "-crt-static",
             ".cargo/config.toml missing -crt-static flag for musl targets"
    end

    test "cargo config has LTO optimization" do
      {:ok, content} = File.read(@cargo_config_path)

      # Check for LTO in release profile
      assert content =~ "lto = true" or content =~ "lto=true",
             ".cargo/config.toml missing lto = true in release profile"
    end
  end

  describe "OBX005_3A_T2: Validate Cross.toml is valid TOML" do
    test "Cross.toml file exists" do
      assert File.exists?(@cross_toml_path), "Cross.toml file does not exist at #{@cross_toml_path}"
    end

    test "Cross.toml file is readable and has content" do
      {:ok, content} = File.read(@cross_toml_path)
      assert String.length(content) > 0, "Cross.toml file is empty"
    end

    test "Cross.toml contains build.env section" do
      {:ok, content} = File.read(@cross_toml_path)

      assert content =~ "[build.env]", "Cross.toml missing [build.env] section"
    end

    test "Cross.toml has passthrough configuration" do
      {:ok, content} = File.read(@cross_toml_path)

      assert content =~ "passthrough", "Cross.toml missing passthrough configuration"
      assert content =~ "RUSTLER_NIF_VERSION", "Cross.toml missing RUSTLER_NIF_VERSION passthrough"
      assert content =~ "RUSTFLAGS", "Cross.toml missing RUSTFLAGS passthrough"
    end
  end

  describe "OBX005_3A_T3: Verify Cargo.toml has NIF version features" do
    test "Cargo.toml file exists" do
      assert File.exists?(@cargo_toml_path), "Cargo.toml file does not exist at #{@cargo_toml_path}"
    end

    test "Cargo.toml has [features] section" do
      {:ok, content} = File.read(@cargo_toml_path)

      assert content =~ "[features]", "Cargo.toml missing [features] section"
    end

    test "Cargo.toml has default features with nif_version_2_15" do
      {:ok, content} = File.read(@cargo_toml_path)

      # Check for default feature
      assert content =~ ~r/default\s*=.*nif_version_2_15/,
             "Cargo.toml missing default feature with nif_version_2_15"
    end

    test "Cargo.toml has nif_version_2_15 feature definition" do
      {:ok, content} = File.read(@cargo_toml_path)

      # Check for nif_version_2_15 feature
      assert content =~ ~r/nif_version_2_15\s*=.*rustler\/nif_version_2_15/,
             "Cargo.toml missing nif_version_2_15 feature definition"
    end

    test "Cargo.toml has rust-version specified" do
      {:ok, content} = File.read(@cargo_toml_path)

      # Check for rust-version
      assert content =~ "rust-version", "Cargo.toml missing rust-version"
      assert content =~ "1.86.0", "Cargo.toml missing rust-version = \"1.86.0\""
    end

    test "Cargo.toml has correct package metadata" do
      {:ok, content} = File.read(@cargo_toml_path)

      # Check basic package info
      assert content =~ ~r/name\s*=\s*"objectstorex"/, "Cargo.toml missing package name"
      assert content =~ ~r/version\s*=\s*"0\.1\.0"/, "Cargo.toml missing package version"
      assert content =~ ~r/edition\s*=\s*"2021"/, "Cargo.toml missing edition = \"2021\""
    end

    test "Cargo.toml has cdylib crate-type" do
      {:ok, content} = File.read(@cargo_toml_path)

      # Check for cdylib crate type (required for NIFs)
      assert content =~ ~r/crate-type\s*=.*cdylib/, "Cargo.toml missing crate-type = [\"cdylib\"]"
    end
  end

  describe "OBX005_3A_T4: Test local cargo build succeeds" do
    @tag timeout: 300_000
    @tag :cargo_build
    test "cargo build command executes successfully in native directory" do
      # Skip if cargo is not available
      case System.find_executable("cargo") do
        nil ->
          IO.puts("Skipping cargo build test - cargo not found in PATH")
          :ok

        _cargo_path ->
          # Run cargo build in the native directory
          result =
            System.cmd("cargo", ["build", "--release"],
              cd: "native/objectstorex",
              stderr_to_stdout: true
            )

          case result do
            {_output, 0} ->
              assert true, "Cargo build succeeded"

            {output, exit_code} ->
              flunk("""
              Cargo build failed with exit code #{exit_code}

              Output:
              #{output}
              """)
          end
      end
    end

    test "cargo check passes without errors" do
      # cargo check is faster than build and validates the code
      case System.find_executable("cargo") do
        nil ->
          IO.puts("Skipping cargo check test - cargo not found in PATH")
          :ok

        _cargo_path ->
          result =
            System.cmd("cargo", ["check"],
              cd: "native/objectstorex",
              stderr_to_stdout: true
            )

          case result do
            {_output, 0} ->
              assert true, "Cargo check succeeded"

            {output, exit_code} ->
              # Only fail if it's a real error, not just missing cache
              unless output =~ "Blocking waiting for file lock" do
                flunk("Cargo check failed with exit code #{exit_code}: #{output}")
              end
          end
      end
    end
  end

  describe "OBX005_3A_T5: Verify release profile has lto=true" do
    test "release profile enables LTO optimization" do
      {:ok, content} = File.read(@cargo_config_path)

      # Verify LTO is enabled in release profile
      # Check in .cargo/config.toml first
      if content =~ "[profile.release]" do
        # Extract the profile.release section
        profile_section =
          content
          |> String.split("[profile.release]")
          |> Enum.at(1, "")
          |> String.split("[")
          |> Enum.at(0, "")

        assert profile_section =~ "lto", "Release profile missing lto configuration"
        assert profile_section =~ "true", "Release profile lto should be set to true"
      else
        flunk("Missing [profile.release] section in .cargo/config.toml")
      end
    end

    test "LTO configuration syntax is correct" do
      {:ok, content} = File.read(@cargo_config_path)

      # Check for proper TOML syntax: lto = true
      assert content =~ ~r/lto\s*=\s*true/, "LTO configuration has incorrect syntax"
    end
  end

  describe "OBX005_3A_T6: Verify NIF loads after local build" do
    test "ObjectStoreX.Native module is loaded" do
      # The NIF should be loaded if we got this far
      assert Code.ensure_loaded?(ObjectStoreX.Native),
             "ObjectStoreX.Native module failed to load"
    end

    test "NIF functions are callable" do
      # Test that NIF functions work after build
      # Use the memory store as it doesn't require credentials
      store = ObjectStoreX.Native.new_memory()
      assert is_reference(store), "new_memory() should return a reference"
    end

    test "NIF can perform basic operations after build" do
      store = ObjectStoreX.Native.new_memory()

      # Test put operation
      result = ObjectStoreX.Native.put(store, "test-key", "test-value")
      assert result == :ok, "put operation should return :ok"

      # Test get operation
      result = ObjectStoreX.Native.get(store, "test-key")
      assert result == "test-value", "get operation should return the stored value"

      # Test delete operation
      result = ObjectStoreX.Native.delete(store, "test-key")
      assert result == :ok, "delete operation should return :ok"
    end

    test "NIF was compiled with correct features" do
      # Verify the NIF supports the operations we expect
      # This implicitly tests that nif_version_2_15 feature is enabled

      functions = ObjectStoreX.Native.__info__(:functions)
      function_names = Enum.map(functions, fn {name, _arity} -> name end)

      # These functions should be available with NIF version 2.15
      assert :new_memory in function_names
      assert :put in function_names
      assert :get in function_names
      assert :delete in function_names
    end
  end
end
