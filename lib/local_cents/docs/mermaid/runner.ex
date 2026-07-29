defmodule LocalCents.Docs.Mermaid.Runner do
  @moduledoc """
  Runs `LocalCents.Docs.Mermaid`'s parse harness: finds a browser, fetches the
  pinned Mermaid build, and drives the two together.

  Everything the check needs from the outside world lives here, so
  `mix docs.mermaid` is left holding only the parts a reader of a Mix task expects
  — arguments, which files to read, and what to print. That separation also keeps
  policy out of the mechanism: `run/1` reports anything that stopped it from
  reaching a verdict as `{:skip, reason}` and leaves the caller to decide whether
  that is a notice or a failure (see the task's `--strict` option). What the check
  is for: [Mermaid Diagrams](mermaid-diagrams.html).

  This is Mix-time tooling, not application code — it writes to `Mix.shell/0` and
  caches under `_build/`, and nothing in the running app calls it.
  """

  alias LocalCents.Docs.Mermaid
  alias LocalCents.Docs.Mermaid.Block

  @cache_dir "_build/mermaid"

  # Enough virtual time for Mermaid to boot and parse every block. Virtual time is
  # not wall-clock: Chrome fast-forwards timers, so this bounds work, not seconds.
  @virtual_time_budget_ms 20_000

  @browser_candidates [
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/Applications/Chromium.app/Contents/MacOS/Chromium",
    "google-chrome",
    "google-chrome-stable",
    "chromium",
    "chromium-browser",
    "chrome"
  ]

  @typedoc """
  `{:skip, reason}` covers every way the check can fail to produce a verdict — no
  browser, an un-fetchable Mermaid, a browser that will not start, a page that
  crashed. They are one outcome on purpose: each leaves the diagrams unchecked,
  and each is a local-environment problem the caller may reasonably tolerate but
  CI must not.
  """
  @type outcome() :: {:ok, Mermaid.results()} | {:skip, String.t()}

  @doc """
  Parses every block in `blocks` and returns each one's verdict.

  Looks for a browser at `CHROME_BIN` first, then in the usual macOS and Linux
  install locations.
  """
  @spec run(blocks :: [Block.t()]) :: outcome()
  def run(blocks) do
    with {:ok, browser} <- find_browser(),
         {:ok, mermaid_js} <- fetch_mermaid() do
      dump_dom(browser, write_harness(blocks, mermaid_js), length(blocks))
    end
  end

  defp find_browser do
    candidate =
      Enum.find_value([System.get_env("CHROME_BIN") | @browser_candidates], fn
        nil -> nil
        candidate -> resolve_executable(candidate)
      end)

    case candidate do
      nil -> {:skip, "no Chrome or Chromium binary was found (set CHROME_BIN to point at one)"}
      browser -> {:ok, browser}
    end
  end

  defp resolve_executable(candidate) do
    cond do
      File.regular?(candidate) -> candidate
      path = System.find_executable(candidate) -> path
      true -> nil
    end
  end

  # Cached by version so a pin bump fetches the new build rather than reusing a
  # stale one, and so CI can cache the directory across runs.
  defp fetch_mermaid do
    path = Path.join(@cache_dir, "mermaid-#{Mermaid.version()}.min.js")

    if File.regular?(path), do: {:ok, path}, else: download(path)
  end

  defp download(path) do
    url = Mermaid.cdn_url()
    Mix.shell().info("Fetching #{url} ...")
    # The app is deliberately not started for a docs check, so Req's supervision
    # tree has to be brought up by hand before the first request.
    {:ok, _apps} = Application.ensure_all_started(:req)

    case Req.get(url, retry: :transient, receive_timeout: 60_000) do
      {:ok, %{status: 200, body: body}} ->
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, body)
        {:ok, path}

      other ->
        {:skip,
         "Mermaid #{Mermaid.version()} could not be fetched from #{url} (#{inspect(other)})"}
    end
  end

  defp write_harness(blocks, mermaid_js) do
    harness = Path.join(@cache_dir, "harness.html")
    File.mkdir_p!(@cache_dir)
    File.write!(harness, Mermaid.harness_html(blocks, Path.basename(mermaid_js)))

    harness
  end

  defp dump_dom(browser, harness, count) do
    Mix.shell().info("Parsing #{count} diagram(s) with Mermaid #{Mermaid.version()} ...")

    case System.cmd(browser, browser_args(harness), env: []) do
      {dom, 0} -> decode(dom)
      {_dom, status} -> {:skip, "#{Path.basename(browser)} exited with status #{status}"}
    end
  end

  defp decode(dom) do
    case Mermaid.decode_results(dom) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:skip, reason}
    end
  end

  defp browser_args(harness) do
    [
      "--headless",
      "--disable-gpu",
      # Required when CI runs as root in a container; harmless otherwise.
      "--no-sandbox",
      "--no-first-run",
      "--no-default-browser-check",
      # The harness loads Mermaid from a sibling `file://` URL.
      "--allow-file-access-from-files",
      # Keep out of the developer's real Chrome profile, which may be in use — and
      # out of `@cache_dir`, which CI caches.
      "--user-data-dir=#{Path.join(System.tmp_dir!(), "local-cents-mermaid-chrome")}",
      "--dump-dom",
      "--virtual-time-budget=#{@virtual_time_budget_ms}",
      "file://#{Path.expand(harness)}"
    ]
  end
end
