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
      usage_rules: usage_rules(),
      # `:boundary` MUST come before `Mix.compilers()`. It installs a compile
      # tracer and an after-compile hook to check cross-boundary calls; if it
      # runs after the Elixir compiler the tracer is never active, so it
      # silently builds an empty view — no violations are caught and
      # `mix boundary.spec` prints nothing. See lib/local_cents.ex and the
      # context modules for the boundary definitions themselves.
      compilers: [:boundary, :phoenix_live_view] ++ Mix.compilers(),
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
        groups_for_modules: groups_for_modules(),
        nest_modules_by_prefix: nest_modules_by_prefix(),
        # The module-boundaries guide names the `Storybook` boundary shim, which
        # is a hidden (`@moduledoc false`) no-op module. Tell ExDoc not to try to
        # autolink it (which would warn).
        skip_code_autolink_to: [
          "Storybook"
        ],
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
      "CONTEXT.md",
      "docs/ui-language.md",
      "docs/software-terms.md",
      "docs/module-boundaries.md",
      "docs/moduledoc-style.md",
      "docs/book-runtime-architecture.md",
      "docs/command-line-history.md",
      "docs/breadboard-demo.md",
      "docs/proposals/mvp.md",
      "docs/adr/about.md",
      "docs/adr/0001-which-automerge-rust-library.md",
      "docs/adr/0002-expense-attributes.md",
      "docs/adr/0003-bond-namespace-location.md",
      "docs/adr/0004-remove-daisyui-hand-authored-components.md",
      "docs/adr/0005-categories-not-tags.md",
      "docs/adr/0006-multi-window-desktop-shell.md",
      "docs/adr/0007-book-runtime-and-persistence.md",
      "docs/adr/0008-mvp-expense-shape.md",
      "docs/adr/0009-book-file-format.md",
      "docs/adr/0010-cost-as-decimal-string.md"
    ]
  end

  # Groups the "Pages" (extras) in the docs sidebar. Anything not matched here
  # (README, API Reference) stays ungrouped at the top.
  defp groups_for_extras do
    [
      Guides:
        ~r{(CONTEXT|docs/(ui-language|software-terms|module-boundaries|moduledoc-style|book-runtime-architecture|command-line-history|breadboard-demo))\.md},
      Proposals: ~r{docs/proposals/},
      Decisions: ~r{docs/adr/}
    ]
  end

  # Groups the "Modules" in the docs sidebar. Order matters: a module lands in
  # the first group it matches, so more specific groups come before the general
  # `Web` catch-all.
  defp groups_for_modules do
    [
      Core: [
        LocalCents,
        LocalCents.Application,
        LocalCents.Mailer
      ],
      Tracking: [~r/^LocalCents\.Tracking/],
      "Bond Components": [~r/^LocalCentsWeb\.Bond/],
      Storybook: [~r/^Storybook/, ~r/^LocalCentsWeb\.Storybook/],
      Web: [~r/^LocalCentsWeb/]
    ]
  end

  # Nests deeply-namespaced modules under a common prefix in the sidebar, so the
  # visible label is just the trailing part (e.g. `LocalCentsWeb.Bond.Elements.Button`
  # displays as `Button`). This keeps long names from being truncated. ExDoc uses
  # the longest matching prefix for each module.
  defp nest_modules_by_prefix do
    [
      LocalCents.Tracking,
      LocalCentsWeb.Bond.Composites,
      LocalCentsWeb.Bond.Elements,
      LocalCentsWeb.Bond.Layouts,
      LocalCentsWeb.Plugs,
      LocalCentsWeb.Storybook
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
      # To help organize and document UI components.
      {:phoenix_storybook, "~> 1.1.0"},

      # For documentation generation.
      {:ex_doc, "~> 0.4", only: :dev, runtime: false, warn_if_outdated: true},

      # For installing/configuring packages and code refactoring via `mix
      # igniter.*` tasks. A dev/test-only tool; not part of the production build.
      {:igniter, "~> 0.8", only: [:dev, :test]},

      # Aggregates dependencies' `usage-rules.md` files into our AGENTS.md so the
      # rules a library ships for AI agents surface in our agent context. Run
      # `mix usage_rules.sync` after changing the config below. See usage_rules/0.
      {:usage_rules, "~> 1.0", only: [:dev]},

      # For test-driven development.
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false},

      # For the `~M` sigil map shorthand (e.g. `~M{conn}` for `%{conn: conn}`),
      # which cuts down on repetition in test setups.
      {:tiny_maps, "~> 3.0", only: :test, runtime: false},

      # For high-level, browser-like feature tests that read as user flows
      # (`visit/2`, `click_button/2`, `fill_in/3`, `assert_has/3`).
      {:phoenix_test, "~> 0.11.1", only: :test, runtime: false},

      # For code logic style and enforcement.
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},

      # For enforcing domain-context isolation at compile time — each context
      # exposes a public API boundary and keeps its internals private.
      {:boundary, "~> 0.10.4", runtime: false},

      # For security scans.
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false},

      # To allow calling Rust code from Elixir.
      {:rustler, "~> 0.38.0"},

      # To help with Tauri integration
      {:elixirkit, github: "livebook-dev/elixirkit"},

      # The Phoenix web framework and LiveView, plus dev/test companions.
      {:phoenix, "~> 1.8.7"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.1.0"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:lazy_html, ">= 0.1.0", only: :test},

      # For building and serving front-end assets.
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},

      # For composing and sending email.
      {:swoosh, "~> 1.16"},

      # The preferred HTTP client for the app.
      {:req, "~> 0.5"},

      # For collecting and reporting runtime metrics.
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},

      # For internationalization and localization.
      {:gettext, "~> 1.0"},

      # For JSON encoding and decoding.
      {:jason, "~> 1.2"},

      # For clustering nodes via DNS.
      {:dns_cluster, "~> 0.2.0"},

      # The HTTP server that runs the Phoenix endpoint.
      {:bandit, "~> 1.5"}
    ]
  end

  # Configures `mix usage_rules.sync`, which aggregates the `usage-rules.md`
  # files that dependencies ship for AI agents into a managed section of
  # AGENTS.md (our CLAUDE.md is a symlink to it). We use link ("jump-out") mode
  # so AGENTS.md gets a pointer to each dependency's rules rather than inlining
  # the full text, keeping the file lean. `:all` auto-discovers every dependency
  # that provides usage rules, so newly added libraries surface on the next sync.
  defp usage_rules do
    [
      file: "AGENTS.md",
      usage_rules: {:all, link: :markdown}
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
