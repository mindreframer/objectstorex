defmodule DistributedCache.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # The cache will be started manually by the user
      # This is just a placeholder application structure
    ]

    opts = [strategy: :one_for_one, name: DistributedCache.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
