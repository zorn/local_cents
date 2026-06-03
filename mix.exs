defmodule LocalCents.MixProject do
  use Mix.Project

  def project do
    [
      app: :local_cents,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {LocalCents.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    # Using the MIX_ENV of `:test` for the `precommit` task is required for
    # running the tests. A unfortunate side effect of this means that the
    # execution of dialyzer and sobelow will run in a `:test` MIX_ENV as well
    # which is not what you see when running `mix dialyzer` or `mix sobelow`
    # directly. This can lead to non-green output that won't come up during CI
    # runs related to test only modules.
    [
      preferred_envs: [
        precommit: :test
      ]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      # For test-driven development.
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # For code logic style and enforcement.
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # For security scans.
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},

      # To allow calling Rust code from Elixir.
      {:rustler, "~> 0.38.0"},

      # To help with Tauri integration
      {:elixirkit, github: "livebook-dev/elixirkit"},

      # Unorganized
      {:phoenix, "~> 1.8.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:swoosh, "~> 1.16"},
      {:req, "~> 0.5"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.2.0"},
      {:bandit, "~> 1.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind local_cents", "esbuild local_cents"],
      "assets.deploy": [
        "tailwind local_cents --minify",
        "esbuild local_cents --minify",
        "phx.digest"
      ],
      precommit: [
        "compile --warnings-as-errors",
        "deps.unlock --unused",
        "format",
        "credo --strict",
        "cmd sh -c 'MIX_ENV=dev mix dialyzer'",
        "sobelow",
        "test"
      ]
    ]
  end
end
