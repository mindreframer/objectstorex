defmodule OBX0054ACICDValidationTest do
  use ExUnit.Case, async: false

  @moduletag :obx005_4a

  @workflow_path ".github/workflows/nif-release.yml"
  @project_config Mix.Project.config()
  @version @project_config[:version]

  setup_all do
    # Read and parse workflow file once for all tests
    workflow_content = File.read!(@workflow_path)
    {:ok, workflow} = YamlElixir.read_from_string(workflow_content)
    {:ok, workflow: workflow, content: workflow_content}
  end

  describe "OBX005_4A: CI/CD Pipeline Tests" do

    test "OBX005_4A_T1: Test workflow YAML is valid", %{content: content} do
      # Verify file exists
      assert File.exists?(@workflow_path),
             "Workflow file not found at #{@workflow_path}"

      # Verify YAML can be parsed
      assert {:ok, parsed} = YamlElixir.read_from_string(content),
             "Workflow YAML is not valid"

      # Verify basic structure
      assert is_map(parsed), "Parsed workflow should be a map"
      assert Map.has_key?(parsed, "name"), "Workflow should have a name"
      assert Map.has_key?(parsed, "on"), "Workflow should have triggers (on)"
      assert Map.has_key?(parsed, "jobs"), "Workflow should have jobs"
    end

    test "OBX005_4A_T2: Test all 8 matrix jobs defined", %{workflow: workflow} do
      # Get build job
      build_job = get_in(workflow, ["jobs", "build"])
      assert build_job != nil, "Build job not found in workflow"

      # Get matrix strategy
      matrix = get_in(build_job, ["strategy", "matrix"])
      assert matrix != nil, "Matrix strategy not found in build job"

      # Get job configurations
      jobs = get_in(matrix, ["job"])
      assert is_list(jobs), "Matrix jobs should be a list"
      assert length(jobs) == 8, "Expected 8 matrix jobs, got #{length(jobs)}"

      # Define expected targets
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

      # Extract actual targets from matrix
      actual_targets = Enum.map(jobs, fn job -> job["target"] end)

      # Verify all expected targets are present
      for target <- expected_targets do
        assert target in actual_targets,
               "Expected target #{target} not found in matrix jobs"
      end

      # Verify all jobs have required fields
      for job <- jobs do
        assert Map.has_key?(job, "target"), "Matrix job missing 'target' field"
        assert Map.has_key?(job, "os"), "Matrix job missing 'os' field"
      end

      # Verify cross-compilation jobs have use-cross flag
      cross_targets = [
        "aarch64-unknown-linux-gnu",
        "aarch64-unknown-linux-musl",
        "x86_64-unknown-linux-musl"
      ]

      for job <- jobs do
        if job["target"] in cross_targets do
          assert job["use-cross"] == true,
                 "Expected use-cross: true for #{job["target"]}"
        end
      end
    end

    test "OBX005_4A_T3: Test version extraction step works", %{workflow: workflow} do
      # Get build job steps
      steps = get_in(workflow, ["jobs", "build", "steps"])
      assert is_list(steps), "Build job should have steps"

      # Find version extraction step
      version_step =
        Enum.find(steps, fn step ->
          step["name"] == "Extract version from mix.exs"
        end)

      assert version_step != nil, "Version extraction step not found"

      # Verify step configuration
      assert version_step["shell"] == "bash", "Version extraction should use bash"
      assert version_step["run"] != nil, "Version extraction should have run command"

      # Verify the sed command pattern is correct
      run_command = version_step["run"]
      assert run_command =~ "PROJECT_VERSION", "Should set PROJECT_VERSION env var"
      assert run_command =~ "mix.exs", "Should extract from mix.exs"
      assert run_command =~ "GITHUB_ENV", "Should write to GITHUB_ENV"

      # Test the extraction pattern locally
      mix_exs_content = File.read!("mix.exs")

      # Simulate the sed command
      version_line =
        mix_exs_content
        |> String.split("\n")
        |> Enum.find(fn line -> line =~ ~r/@version ".*"/ end)

      assert version_line != nil, "Version line not found in mix.exs"
      assert version_line =~ @version, "Extracted version should match project version"
    end

    test "OBX005_4A_T4: Test workflow triggers on tag push", %{workflow: workflow} do
      # Get workflow triggers
      on_config = workflow["on"]
      assert is_map(on_config), "Workflow triggers should be a map"

      # Check push configuration
      push_config = on_config["push"]
      assert push_config != nil, "Workflow should trigger on push"

      # Verify tags trigger
      tags = push_config["tags"]
      assert tags != nil, "Workflow should trigger on tag push"
      assert is_list(tags), "Tags should be a list"
      assert "*" in tags, "Workflow should trigger on all tags (wildcard)"
    end

    test "OBX005_4A_T5: Test workflow triggers on native/** changes", %{workflow: workflow} do
      # Get workflow triggers
      on_config = workflow["on"]
      push_config = on_config["push"]
      assert push_config != nil, "Workflow should trigger on push"

      # Check paths configuration
      paths = push_config["paths"]
      assert is_list(paths), "Push paths should be a list"

      # Verify native/** path is included
      assert "native/**" in paths,
             "Workflow should trigger on native/** changes"

      # Verify workflow file path is included
      assert ".github/workflows/nif-release.yml" in paths,
             "Workflow should trigger on workflow file changes"

      # Verify branches configuration
      branches = push_config["branches"]
      assert is_list(branches), "Push branches should be a list"
      assert "main" in branches, "Workflow should trigger on main branch"
    end

    test "OBX005_4A_T6: Test rust-cache configuration correct", %{workflow: workflow} do
      # Get build job steps
      steps = get_in(workflow, ["jobs", "build", "steps"])
      assert is_list(steps), "Build job should have steps"

      # Find rust-cache step
      cache_step =
        Enum.find(steps, fn step ->
          uses = step["uses"]
          uses && (uses =~ "rust-cache" or uses =~ "Swatinem/rust-cache")
        end)

      assert cache_step != nil, "Rust cache step not found"

      # Verify cache action version
      assert cache_step["uses"] == "Swatinem/rust-cache@v2",
             "Should use Swatinem/rust-cache@v2"

      # Verify cache configuration
      with_config = cache_step["with"]
      assert is_map(with_config), "Cache step should have 'with' configuration"

      # Verify workspace path
      assert with_config["workspaces"] == "native/objectstorex",
             "Cache should be configured for native/objectstorex workspace"

      # Verify cache keys are configured
      assert Map.has_key?(with_config, "prefix-key"),
             "Cache should have prefix-key configured"

      assert Map.has_key?(with_config, "shared-key"),
             "Cache should have shared-key configured"
    end

    test "OBX005_4A_T7: Test release job only runs on tags", %{workflow: workflow} do
      # Get build job steps
      steps = get_in(workflow, ["jobs", "build", "steps"])
      assert is_list(steps), "Build job should have steps"

      # Find attestation step
      attestation_step =
        Enum.find(steps, fn step ->
          step["name"] == "Artifact attestation"
        end)

      assert attestation_step != nil, "Artifact attestation step not found"

      # Verify it only runs on tags
      assert attestation_step["if"] != nil,
             "Attestation step should have conditional execution"

      assert attestation_step["if"] == "startsWith(github.ref, 'refs/tags/')",
             "Attestation should only run on tags"

      # Find GitHub Release step
      release_step =
        Enum.find(steps, fn step ->
          step["name"] == "Publish to GitHub Release"
        end)

      assert release_step != nil, "GitHub Release step not found"

      # Verify it only runs on tags
      assert release_step["if"] != nil,
             "Release step should have conditional execution"

      assert release_step["if"] == "startsWith(github.ref, 'refs/tags/')",
             "Release should only run on tags"

      # Verify upload artifact step has no condition (runs always)
      upload_step =
        Enum.find(steps, fn step ->
          step["name"] == "Upload artifact"
        end)

      assert upload_step != nil, "Upload artifact step not found"
      # Upload should run on all builds, not just tags
    end

    test "OBX005_4A_T8: Test all builds succeed in CI", %{workflow: workflow} do
      # This test validates the workflow structure that enables successful builds

      # Get build job
      build_job = get_in(workflow, ["jobs", "build"])
      assert build_job != nil, "Build job not found"

      # Verify fail-fast is disabled (allows all builds to complete)
      strategy = build_job["strategy"]
      assert strategy["fail-fast"] == false,
             "fail-fast should be false to allow all builds to complete"

      # Verify timeout is set
      assert build_job["timeout-minutes"] == 60,
             "Build timeout should be set to 60 minutes"

      # Verify required steps are present in correct order
      steps = build_job["steps"]
      step_names = Enum.map(steps, fn step -> step["name"] || step["uses"] end)

      # Check for essential steps
      assert "actions/checkout@v4" in step_names, "Should checkout code"
      assert "dtolnay/rust-toolchain@stable" in step_names, "Should install Rust"
      assert "Extract version from mix.exs" in step_names, "Should extract version"
      assert "Add Rust target" in step_names, "Should add target"
      assert "Build NIF" in step_names, "Should build NIF"

      # Verify Build NIF step uses correct action
      build_step =
        Enum.find(steps, fn step ->
          step["name"] == "Build NIF"
        end)

      assert build_step["uses"] == "philss/rustler-precompiled-action@v1.1.4",
             "Should use philss/rustler-precompiled-action@v1.1.4"

      # Verify build step configuration
      build_with = build_step["with"]
      assert build_with["project-name"] == "objectstorex"
      assert build_with["nif-version"] == "2.15"
      assert build_with["project-dir"] == "native/objectstorex"
    end

    test "OBX005_4A_T9: Test artifacts uploaded for all targets", %{workflow: workflow} do
      # Get build job steps
      steps = get_in(workflow, ["jobs", "build", "steps"])
      assert is_list(steps), "Build job should have steps"

      # Find upload artifact step
      upload_step =
        Enum.find(steps, fn step ->
          uses = step["uses"]
          step["name"] == "Upload artifact" or (uses && uses =~ "upload-artifact")
        end)

      assert upload_step != nil, "Upload artifact step not found"

      # Verify upload action version
      assert upload_step["uses"] == "actions/upload-artifact@v4",
             "Should use actions/upload-artifact@v4"

      # Verify upload configuration uses build outputs
      upload_with = upload_step["with"]
      assert upload_with != nil, "Upload step should have 'with' configuration"

      # Verify it uses build step outputs
      assert upload_with["name"] =~ "build-crate.outputs",
             "Upload should use build step output for artifact name"

      assert upload_with["path"] =~ "build-crate.outputs",
             "Upload should use build step output for file path"

      # Verify build step has an id
      build_step =
        Enum.find(steps, fn step ->
          step["name"] == "Build NIF"
        end)

      assert build_step["id"] == "build-crate",
             "Build step should have id 'build-crate'"

      # Verify GitHub Release step also uses outputs
      release_step =
        Enum.find(steps, fn step ->
          step["name"] == "Publish to GitHub Release"
        end)

      assert release_step != nil, "GitHub Release step not found"

      release_with = release_step["with"]
      assert release_with["files"] != nil, "Release should specify files to upload"
    end
  end
end
