# Contributing to ObjectStoreX

Thank you for your interest in contributing to ObjectStoreX! This document provides guidelines and instructions for contributing.

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Running Tests](#running-tests)
- [Code Style](#code-style)
- [Pull Request Process](#pull-request-process)
- [Reporting Issues](#reporting-issues)

## Code of Conduct

Be respectful and constructive in all interactions. We aim to maintain a welcoming and inclusive community.

## Getting Started

1. Fork the repository on GitHub
2. Clone your fork locally
3. Create a new branch for your feature or bug fix
4. Make your changes
5. Run tests and quality checks
6. Submit a pull request

## Development Setup

### Prerequisites

- Elixir 1.14 or later
- Erlang/OTP 25 or later
- Rust 1.70 or later (for building NIFs)
- Git

### Setup Instructions

```bash
# Clone your fork
git clone https://github.com/your-username/objectstorex.git
cd objectstorex

# Install Elixir dependencies
mix deps.get

# Compile the project (builds Rust NIFs)
mix compile

# Run tests to verify setup
mix test
```

### Building the Rust NIFs

The Rust NIFs are built automatically during `mix compile`. To build manually:

```bash
cd native/objectstorex
cargo build
```

## Running Tests

### Run All Tests

```bash
mix test
```

### Run Specific Test File

```bash
mix test test/objectstorex_test.exs
```

### Run Tests with Coverage

```bash
mix coveralls
mix coveralls.html  # Generate HTML coverage report
```

### Run Integration Tests

Integration tests that require cloud provider credentials:

```bash
# Run S3 integration tests (requires AWS credentials)
mix test --only s3

# Run all integration tests
mix test --include cloud
```

### Run Quality Checks

We use a QA script that runs all quality checks:

```bash
./bin/qa_check.sh
```

This runs:
- `mix test` - Unit tests
- `mix format --check-formatted` - Code formatting
- `mix credo --strict` - Static analysis
- `mix dialyzer` - Type checking
- Rust tests and clippy

## Code Style

### Elixir Code Style

We follow the standard Elixir style guide:

- Use `mix format` before committing
- Follow naming conventions:
  - Modules: `PascalCase`
  - Functions: `snake_case`
  - Variables: `snake_case`
  - Private functions: prefix with underscore
- Write @doc for all public functions
- Write @spec for all public functions
- Maximum line length: 120 characters

### Rust Code Style

- Use `cargo fmt` before committing
- Run `cargo clippy` and fix all warnings
- Follow Rust naming conventions
- Document public functions with doc comments

### Example Elixir Code

```elixir
defmodule ObjectStoreX.Example do
  @moduledoc """
  Example module documentation.
  """

  @doc """
  Example function documentation.

  ## Examples

      iex> ObjectStoreX.Example.do_something("input")
      {:ok, "output"}
  """
  @spec do_something(String.t()) :: {:ok, String.t()} | {:error, atom()}
  def do_something(input) do
    # Implementation
  end
end
```

## Pull Request Process

### Before Submitting

1. Ensure all tests pass: `mix test`
2. Run quality checks: `./bin/qa_check.sh`
3. Update documentation if needed
4. Add tests for new features
5. Update CHANGELOG.md

### Commit Message Format

Use clear, descriptive commit messages:

```
[Component] Brief description

Detailed explanation of changes if needed.

Fixes #123
```

Examples:
- `[Core] Add support for streaming uploads`
- `[Docs] Update configuration guide for Azure`
- `[Tests] Add integration tests for GCS`
- `[Fix] Handle timeout errors correctly`

### Pull Request Checklist

- [ ] Tests added/updated and passing
- [ ] Documentation updated
- [ ] CHANGELOG.md updated
- [ ] Code formatted (`mix format`)
- [ ] No Credo warnings (`mix credo --strict`)
- [ ] No Dialyzer warnings (`mix dialyzer`)
- [ ] Rust code formatted (`cargo fmt`)
- [ ] No clippy warnings (`cargo clippy`)

### Review Process

1. Submit your pull request
2. Maintainers will review your changes
3. Address any feedback
4. Once approved, your PR will be merged

## Reporting Issues

### Bug Reports

When reporting a bug, please include:

- **Description**: Clear description of the bug
- **Steps to Reproduce**: Minimal steps to reproduce the issue
- **Expected Behavior**: What you expected to happen
- **Actual Behavior**: What actually happened
- **Environment**:
  - ObjectStoreX version
  - Elixir version
  - Erlang/OTP version
  - Operating system
  - Provider (S3, Azure, GCS, etc.)
- **Logs/Error Messages**: Any relevant error messages or stack traces

### Feature Requests

When requesting a feature:

- **Use Case**: Describe the problem you're trying to solve
- **Proposed Solution**: Your suggested implementation
- **Alternatives**: Other solutions you've considered
- **Additional Context**: Any other relevant information

## Development Guidelines

### Testing Guidelines

- Write tests for all new features
- Maintain or improve test coverage (target: >80%)
- Use descriptive test names
- Test both success and error cases
- Test edge cases

Example test:

```elixir
defmodule ObjectStoreX.ExampleTest do
  use ExUnit.Case, async: true

  describe "do_something/1" do
    test "returns ok with valid input" do
      assert {:ok, result} = ObjectStoreX.Example.do_something("input")
      assert result == "expected"
    end

    test "returns error with invalid input" do
      assert {:error, :invalid_input} = ObjectStoreX.Example.do_something(nil)
    end
  end
end
```

### Documentation Guidelines

- Write clear, concise documentation
- Include examples in @doc
- Update guides when adding features
- Keep README.md up to date
- Use proper Markdown formatting

### Error Handling Guidelines

- Return tagged tuples: `{:ok, result}` or `{:error, reason}`
- Use descriptive error atoms
- Provide error context when helpful
- Document all error cases

## Working with Cloud Providers

### Setting Up Test Accounts

For integration testing, you'll need test accounts:

**AWS S3:**
```bash
export AWS_ACCESS_KEY_ID="your-key"
export AWS_SECRET_ACCESS_KEY="your-secret"
export TEST_S3_BUCKET="objectstorex-test"
```

**Azure:**
```bash
export AZURE_STORAGE_ACCOUNT="your-account"
export AZURE_STORAGE_KEY="your-key"
export TEST_AZURE_CONTAINER="objectstorex-test"
```

**GCS:**
```bash
export GCP_SERVICE_ACCOUNT_KEY="$(cat credentials.json)"
export TEST_GCS_BUCKET="objectstorex-test"
```

### Integration Test Guidelines

- Tag cloud tests: `@tag :cloud`
- Clean up resources after tests
- Use unique object names to avoid conflicts
- Handle rate limits gracefully

## Getting Help

- **Documentation**: Check the [guides](guides/)
- **Issues**: Search existing issues before creating new ones
- **Discussions**: Use GitHub Discussions for questions

## License

By contributing to ObjectStoreX, you agree that your contributions will be licensed under the Apache 2.0 License.

## Recognition

Contributors will be recognized in:
- CHANGELOG.md
- GitHub contributors page
- Release notes

Thank you for contributing to ObjectStoreX!
