defmodule PackageValidationTest do
  use ExUnit.Case, async: false

  @moduletag :package_validation

  @version Mix.Project.config()[:version]
  @app Mix.Project.config()[:app]

  describe "OBX004_5A: Hex Package Preparation" do
    test "OBX004_5A_T1: Test hex build succeeds" do
      # Clean up any previous build artifacts
      File.rm_rf("#{@app}-#{@version}.tar")

      # Run hex build (without --unpack to get checksum)
      {output, exit_code} = System.cmd("mix", ["hex.build"], stderr_to_stdout: true)

      # Assert build succeeds
      assert exit_code == 0, "Hex build failed with output: #{output}"
      assert output =~ "Building #{@app} #{@version}", "Unexpected build output"
      assert output =~ "Package checksum:", "Missing package checksum"
      assert output =~ "Saved to #{@app}-#{@version}.tar", "Tarball save message missing"

      # Verify the tarball was created
      assert File.exists?("#{@app}-#{@version}.tar"),
             "Package tarball not created"

      # Clean up
      File.rm("#{@app}-#{@version}.tar")
    end

    test "OBX004_5A_T2: Test package includes all necessary files" do
      # Build the package
      {output, _} = System.cmd("mix", ["hex.build", "--unpack"], stderr_to_stdout: true)

      # Extract required files from build output
      required_files = [
        "lib",
        "native/objectstorex/src",
        "native/objectstorex/Cargo.toml",
        "native/objectstorex/Cargo.lock",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md"
      ]

      # Check each required file is mentioned in the build output
      for file <- required_files do
        assert output =~ file,
               "Required file/directory '#{file}' not included in package"
      end

      # Verify Elixir source files are included
      assert output =~ "lib/objectstorex.ex", "Main module not included"
      assert output =~ "lib/objectstorex/error.ex", "Error module not included"

      # Verify Rust source files are included
      assert output =~ "native/objectstorex/src/lib.rs", "Rust lib.rs not included"

      # Clean up
      File.rm("#{@app}-#{@version}.tar")
    end

    test "OBX004_5A_T3: Test package metadata is complete" do
      # Build the package to get metadata output
      {output, _} = System.cmd("mix", ["hex.build", "--unpack"], stderr_to_stdout: true)

      # Verify essential metadata fields
      assert output =~ "App: #{@app}", "App name missing"
      assert output =~ "Version: #{@version}", "Version missing"
      assert output =~ "Description:", "Description missing"
      assert output =~ "Licenses: Apache-2.0", "License missing or incorrect"

      # Verify description content
      assert output =~ "Unified object storage", "Description incomplete"
      assert output =~ "Rust's object_store library", "Description missing Rust mention"

      # Verify links
      assert output =~ "GitHub:", "GitHub link missing"
      assert output =~ "Changelog:", "Changelog link missing"

      # Verify Elixir version requirement
      assert output =~ "Elixir: ~> 1.14", "Elixir version requirement missing"

      # Verify maintainers
      project_config = Mix.Project.config()
      package_config = project_config[:package]
      assert package_config[:maintainers] != nil, "Maintainers not configured"
      assert package_config[:maintainers] != ["Your Name"], "Placeholder maintainer not updated"

      # Clean up
      File.rm("#{@app}-#{@version}.tar")
    end

    test "OBX004_5A_T4: Test documentation builds correctly" do
      # Clean previous docs
      File.rm_rf("doc")

      # Build documentation
      {output, exit_code} = System.cmd("mix", ["docs"], stderr_to_stdout: true)

      # Assert docs build succeeds
      assert exit_code == 0, "Documentation build failed with output: #{output}"

      # Verify doc directory was created
      assert File.exists?("doc"), "Documentation directory not created"
      assert File.exists?("doc/index.html"), "Documentation index not created"

      # Verify main module documentation exists
      assert File.exists?("doc/ObjectStoreX.html"), "ObjectStoreX module docs not generated"

      # Verify guides are included
      doc_index = File.read!("doc/index.html")

      # Check for guides in the documentation
      guides = [
        "Getting Started",
        "Configuration",
        "Streaming",
        "Distributed Systems",
        "Error Handling"
      ]

      for guide <- guides do
        assert doc_index =~ guide or File.exists?("doc/#{String.downcase(String.replace(guide, " ", "_"))}.html"),
               "Guide '#{guide}' not found in documentation"
      end

      # Verify key modules are documented
      modules = [
        "ObjectStoreX",
        "ObjectStoreX.Stream",
        "ObjectStoreX.Error"
      ]

      for module <- modules do
        module_file = "doc/#{module}.html"
        assert File.exists?(module_file), "Module documentation not found: #{module_file}"
      end
    end

    test "OBX004_5A_T5: Test README badges render correctly" do
      # Read README content
      readme_path = Path.join(File.cwd!(), "README.md")
      assert File.exists?(readme_path), "README.md not found"

      readme_content = File.read!(readme_path)

      # Verify README has badges section at the top
      required_badges = [
        # Hex.pm badge
        ~r/\[!\[Hex\.pm\]/,
        # Documentation badge
        ~r/\[!\[Documentation\]/,
        # CI badge
        ~r/\[!\[CI\]/,
        # Coverage badge
        ~r/\[!\[Coverage\]/,
        # License badge
        ~r/\[!\[License\]/
      ]

      for badge_pattern <- required_badges do
        assert readme_content =~ badge_pattern,
               "README missing required badge matching pattern: #{inspect(badge_pattern)}"
      end

      # Verify badge links are properly formatted
      assert readme_content =~ "https://hex.pm/packages/objectstorex",
             "Hex.pm badge link incorrect"

      assert readme_content =~ "https://hexdocs.pm/objectstorex",
             "Documentation badge link incorrect"

      # Verify README structure
      required_sections = [
        "# ObjectStoreX",
        "## Features",
        "## Installation",
        "## Quick Start",
        "## License"
      ]

      for section <- required_sections do
        assert readme_content =~ section,
               "README missing required section: #{section}"
      end

      # Verify installation instructions include correct package name
      assert readme_content =~ "{:objectstorex, \"~> #{@version}\"}",
             "Installation instructions missing or incorrect"

      # Verify license section mentions Apache 2.0
      assert readme_content =~ "Apache",
             "License section doesn't mention Apache license"
    end
  end
end
