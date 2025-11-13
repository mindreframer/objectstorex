defmodule ObjectStoreX.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/mindreframer/objectstorex"
  @dev? String.ends_with?(@version, "-dev")
  @force_build? System.get_env("OBJECTSTOREX_BUILD") in ["1", "true"]

  def project do
    [
      app: :objectstorex,
      version: @version,
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      elixirc_paths: elixirc_paths(Mix.env()),

      # Hex
      description: description(),
      package: package(),

      # Docs
      name: "ObjectStoreX",
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/objectstorex",
      docs: docs(),

      # Testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.json": :test
      ],

      # Dialyzer
      dialyzer: [
        plt_add_apps: [:mix],
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"}
      ]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(:test), do: ["lib", "examples", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:rustler, "~> 0.35.0", optional: not (@dev? or @force_build?), runtime: false},
      {:rustler_precompiled, "~> 0.7"},
      {:jason, "~> 1.4"},

      # Dev/Test
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:yaml_elixir, "~> 2.9", only: :test}
    ]
  end

  defp description do
    """
    Unified object storage for AWS S3, Azure Blob Storage, Google Cloud Storage,
    and local filesystem. Powered by Rust's object_store library via Rustler NIFs.
    Includes streaming, CAS operations, conditional operations, and comprehensive error handling.
    """
  end

  defp package do
    [
      name: "objectstorex",
      files: [
        "lib",
        "native/objectstorex/src",
        "native/objectstorex/.cargo",
        "native/objectstorex/Cargo.toml",
        "native/objectstorex/Cargo.lock",
        "native/objectstorex/Cross.toml",
        "mix.exs",
        "README.md",
        "LICENSE",
        "CHANGELOG.md",
        "checksum-Elixir.ObjectStoreX.Native.exs"
      ],
      maintainers: ["ObjectStoreX Contributors"],
      licenses: ["Apache-2.0"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md"
      }
    ]
  end

  defp docs do
    [
      main: "ObjectStoreX",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        "README.md",
        "CHANGELOG.md",
        "CONTRIBUTING.md",
        "guides/getting_started.md",
        "guides/configuration.md",
        "guides/streaming.md",
        "guides/distributed_systems.md",
        "guides/error_handling.md"
      ],
      groups_for_extras: [
        Guides: Path.wildcard("guides/*.md")
      ],
      groups_for_modules: [
        "Core API": [ObjectStoreX],
        Streaming: [ObjectStoreX.Stream],
        "Error Handling": [ObjectStoreX.Error],
        Internal: [
          ObjectStoreX.Native,
          ObjectStoreX.PutMode,
          ObjectStoreX.GetOptions,
          ObjectStoreX.Range,
          ObjectStoreX.Attributes
        ]
      ]
    ]
  end

  defp aliases do
    [
      "gen.checksum": "rustler_precompiled.download ObjectStoreX.Native --all --print"
    ]
  end
end
