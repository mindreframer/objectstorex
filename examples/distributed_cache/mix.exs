defmodule DistributedCache.MixProject do
  use Mix.Project

  def project do
    [
      app: :distributed_cache,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {DistributedCache.Application, []}
    ]
  end

  defp deps do
    [
      {:objectstorex, path: "../.."}
    ]
  end
end
