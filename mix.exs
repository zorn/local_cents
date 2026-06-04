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
      listeners: [Phoenix.CodeReloader],

      # Docs
      name: "LocalCents",
      source_url: "https://github.com/zorn/local_cents",
      # homepage_url: "https://github.com/zorn/local_cents",
      docs: [
        # can be changed to a module name, if you prefer
        main: "readme",
        extras: extras(),
        groups_for_extras: groups_for_extras(),
        assets: %{"docs/images" => "images"},
        before_closing_head_tag: &before_closing_head_tag/1,
        before_closing_body_tag: &before_closing_body_tag/1
      ]
    ]
  end

  defp before_closing_head_tag(:html) do
    """
    <script defer src="https://cdn.jsdelivr.net/npm/mermaid@10.2.3/dist/mermaid.min.js"></script>
    <script>
      let initialized = false;

      window.addEventListener("exdoc:loaded", () => {
        if (!initialized) {
          mermaid.initialize({
            startOnLoad: false,
            securityLevel: "strict",
            theme: document.body.className.includes("dark") ? "dark" : "default"
          });
          initialized = true;
        }

        let id = 0;
        for (const codeEl of document.querySelectorAll("pre code.mermaid")) {
          const preEl = codeEl.parentElement;
          const graphDefinition = codeEl.textContent;
          const graphEl = document.createElement("div");
          const graphId = "mermaid-graph-" + id++;
          mermaid.render(graphId, graphDefinition).then(({svg, bindFunctions}) => {
            graphEl.innerHTML = svg;
            bindFunctions?.(graphEl);
            preEl.insertAdjacentElement("afterend", graphEl);
            preEl.remove();
          });
        }
      });
    </script>
    """
  end

  defp before_closing_head_tag(_), do: ""

  defp before_closing_body_tag(:html) do
    """
    <!-- HTML injected at the end of the <body> element -->
    """
  end

  defp before_closing_body_tag(_), do: ""

  defp extras do
    [
      "README.md",
      "docs/ubiquitous-language.md",
      "docs/command-line-history.md",
      "docs/breadboard-demo.md",
      "docs/decisions/about.md",
      "docs/decisions/1-which-automerge-rust-library.md"
    ]
  end

  defp groups_for_extras do
    [
      Decisions: ~r/docs\/decisions\/[^\/]+\.md/
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
    # running the tests. An unfortunate side effect is that tasks executed
    # in-process (e.g. Sobelow) also run under `MIX_ENV=test`, which can
    # produce different results than running `mix sobelow` directly in dev.
    # Dialyzer is executed in a separate `MIX_ENV=dev` mix invocation below.
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
      # For documentation generation.
      {:ex_doc, "~> 0.4", only: :dev, runtime: false, warn_if_outdated: true},

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
        "deps.unlock --check-unused",
        "format",
        "credo --strict",
        "cmd sh -c 'MIX_ENV=dev mix dialyzer'",
        "sobelow --config",
        "test"
      ]
    ]
  end
end
