defmodule XtouchMapper.MixProject do
  use Mix.Project

  def project do
    [
      app: :xtouch_mapper,
      version: "0.1.0",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [xtouch_mapper: []]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      mod: {XtouchMapper, []},
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [{:dialyxir, "~> 1.1", only: [:dev], runtime: false}]
  end
end
