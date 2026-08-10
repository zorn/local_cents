defmodule LocalCents.Docs.Mermaid.Runner do
  @moduledoc """
  Runs `LocalCents.Docs.Mermaid`'s parse harness: finds a browser, fetches the
  pinned Mermaid build, and drives the two together.

  Everything the check needs from the outside world is gathered here, which leaves
  the rest of it — arguments, which files to read, what to print — free of any of
  that. The split also keeps policy out of the mechanism: `run/1` reports anything
  that stopped it from reaching a verdict as `{:skip, reason}` and decides nothing
  about whether that is a notice or a failure. What the check is for:
  [Mermaid Diagrams](mermaid-diagrams.html).

  This is Mix-time tooling, not application code — it writes to `Mix.shell/0` and
  caches under `_build/`, and nothing in the running app calls it.
  """

  alias LocalCents.Docs.Mermaid
  alias LocalCents.Docs.Mermaid.Block

  @cache_dir "_build/mermaid"

  # Wall-clock ceiling on one browser run. `--dump-dom` prints the finished DOM in
  # well under a second, so this is not how long a run takes — it is the cutoff for
  # a browser that never dumps at all (a load that hangs, a crash), past which the
  # run is reported as a skip rather than left to block.
  @deadline_ms 30_000

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
    with :ok <- ensure_unix(),
         {:ok, browser} <- find_browser(),
         {:ok, mermaid_js} <- fetch_mermaid() do
      run_dir = run_dir()

      try do
        dump_dom(browser, write_harness(run_dir, blocks, mermaid_js), run_dir, length(blocks))
      after
        File.rm_rf(run_dir)
      end
    end
  end

  # `capture_dom/2` drives the browser with a POSIX shell and stops it with `kill`,
  # so the check runs on Unix-like systems only. On Windows it skips here rather
  # than crashing `mix precommit` at one of those calls — the same graceful skip a
  # missing browser gets — and CI enforces the check on Linux.
  defp ensure_unix do
    case :os.type() do
      {:unix, _flavor} -> :ok
      _other -> {:skip, "the Mermaid check runs on Unix-like systems only"}
    end
  end

  # Everything one run scribbles — the harness page and Chrome's profile — lives
  # under a directory named for the OS process, so two checks running at once
  # cannot read each other's harness or contend for Chrome's profile lock. That
  # happens more here than it sounds: several agents may share one working
  # directory, and a hand-run check can overlap a `mix precommit`. Only the
  # Mermaid bundle is shared, and it is written once and then only read.
  defp run_dir, do: Path.join(System.tmp_dir!(), "local-cents-mermaid-#{System.pid()}")

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

  defp write_harness(run_dir, blocks, mermaid_js) do
    harness = Path.join(run_dir, "harness.html")
    File.mkdir_p!(run_dir)
    File.write!(harness, Mermaid.harness_html(blocks, "file://#{Path.expand(mermaid_js)}"))

    harness
  end

  defp dump_dom(browser, harness, run_dir, count) do
    Mix.shell().info("Parsing #{count} diagram(s) with Mermaid #{Mermaid.version()} ...")

    capture_dom(browser, browser_args(harness, run_dir))
  end

  # Chrome 132 dropped the old headless mode, so `--headless` now runs the new one
  # (https://developer.chrome.com/blog/removing-headless-old-from-chrome); the old
  # dump-and-exit behavior survives only as the separate `chrome-headless-shell`
  # binary. Under new headless, `--dump-dom` prints the finished DOM but then
  # lingers instead of exiting — observed on the Chromium we run, not a documented
  # contract — so a blocking `System.cmd` never returns. The browser is driven
  # through a Port instead, its stdout read as it streams, and the run stops the
  # instant the dumped DOM decodes to the harness's verdict. A browser that never
  # dumps is bounded by `@deadline_ms` and reported as a skip. stderr is dropped: a
  # headless browser narrates to it, and none of that is the check's to print.
  defp capture_dom(browser, args) do
    port =
      Port.open({:spawn_executable, "/bin/sh"}, [
        :binary,
        :exit_status,
        :hide,
        args: ["-c", ~s(exec "$0" "$@" 2>/dev/null), browser | args]
      ])

    {:os_pid, os_pid} = Port.info(port, :os_pid)
    deadline = System.monotonic_time(:millisecond) + @deadline_ms
    collect(port, os_pid, "", deadline)
  end

  defp collect(port, os_pid, dom, deadline) do
    receive do
      {^port, {:data, chunk}} ->
        dom = dom <> chunk

        case Mermaid.decode_results(dom) do
          {:ok, results} -> halt(port, os_pid, {:ok, results})
          {:error, _reason} -> collect(port, os_pid, dom, deadline)
        end

      # An older Chromium that still exits on its own lands here; judge by whatever
      # it dumped before leaving rather than treating the exit itself as a verdict.
      {^port, {:exit_status, _status}} ->
        decode(dom)
    after
      max(deadline - System.monotonic_time(:millisecond), 0) ->
        halt(
          port,
          os_pid,
          {:skip, "the browser reported no parse results within #{@deadline_ms}ms"}
        )
    end
  end

  # Kills the browser — it will not leave on its own — and closes the Port so its
  # helper processes lose their parent and follow. `Port.info/1` guards the close:
  # a browser that already exited has closed the Port, and closing it twice raises.
  defp halt(port, os_pid, result) do
    System.cmd("kill", ["-KILL", Integer.to_string(os_pid)], env: [], stderr_to_stdout: true)
    if Port.info(port), do: Port.close(port)
    result
  end

  defp decode(dom) do
    case Mermaid.decode_results(dom) do
      {:ok, results} -> {:ok, results}
      {:error, reason} -> {:skip, reason}
    end
  end

  defp browser_args(harness, run_dir) do
    [
      "--headless",
      "--disable-gpu",
      # Required when CI runs as root in a container; harmless otherwise.
      "--no-sandbox",
      "--no-first-run",
      "--no-default-browser-check",
      # The harness pulls Mermaid from the cache by absolute `file://` URL, which
      # is a different directory than its own.
      "--allow-file-access-from-files",
      # Keep out of the developer's real Chrome profile, which may be in use.
      "--user-data-dir=#{Path.join(run_dir, "chrome-profile")}",
      "--dump-dom",
      "file://#{Path.expand(harness)}"
    ]
  end
end
