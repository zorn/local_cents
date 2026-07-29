defmodule LocalCentsWeb.DevDocs do
  @moduledoc """
  Whether the generated docs are there and current, and how to rebuild them.

  ExDoc writes to the gitignored `doc/` directory, which the endpoint serves in
  development so the debug bar can link to it (see
  [ADR 0023](0023-browser-as-a-second-client.html)). That directory is a build artifact:
  a fresh clone has none until `mix docs` runs, and any that exist go out of date as soon
  as a moduledoc is edited. Rather than let the Docs link dead-end in a 404 or, worse,
  quietly serve yesterday's prose, `LocalCentsWeb.DevDocsLive` asks here first.

  Staleness is decided by modification time: `doc/index.html` is rewritten on every
  generation, so anything under `@source_globs` newer than it has not made it into the
  docs yet. That is advisory, not exact — touching a file without changing it counts —
  which is the right trade for a prompt whose only cost of being wrong is an unnecessary
  rebuild.

  Development only. `generate/0` shells out to `mix`, which exists in a dev checkout and
  not in a release; nothing routes here outside the `:dev_routes` scope.
  """

  @index "doc/index.html"

  # What ExDoc reads: the source it documents, the extras listed in `mix.exs`, and
  # `mix.exs` itself, since it carries the docs configuration.
  @source_globs ["mix.exs", "*.md", "lib/**/*.ex", "docs/**/*.md"]

  @typedoc """
  The state of the generated docs: never built, built but behind the sources that
  changed since, or current.
  """
  @type status() ::
          :missing
          | {:stale, generated_at :: DateTime.t(), changed :: [Path.t()]}
          | {:fresh, generated_at :: DateTime.t()}

  @doc """
  Reports whether the docs are missing, stale, or current.

  `root` is the project directory to inspect, defaulting to the one the server is
  running in.
  """
  @spec status(root :: Path.t()) :: status()
  def status(root \\ ".") do
    case generated_at(root) do
      nil ->
        :missing

      generated_at ->
        case changed_since(root, generated_at) do
          [] -> {:fresh, generated_at}
          changed -> {:stale, generated_at, changed}
        end
    end
  end

  @doc """
  Runs `mix docs`, returning its combined output either way.

  A separate OS process rather than `Mix.Task.run/2` in the caller: generation compiles,
  and doing that inside the running server's own process would mean recompiling the app
  underneath itself. Blocks for as long as ExDoc takes, so callers should run it off the
  LiveView process.
  """
  @spec generate(root :: Path.t()) :: {:ok, String.t()} | {:error, String.t()}
  def generate(root \\ ".") do
    opts = [cd: root, env: [{"MIX_ENV", "dev"}], stderr_to_stdout: true]

    case System.cmd("mix", ["docs"], opts) do
      {output, 0} -> {:ok, output}
      {output, _status} -> {:error, output}
    end
  end

  @doc "Where the generated docs are served from."
  @spec index_path() :: String.t()
  def index_path, do: "/" <> @index

  # The time of the last generation, or nil if there has never been one. `mtime` comes
  # back as a unix timestamp because of the `time: :posix` option.
  defp generated_at(root) do
    case File.stat(Path.join(root, @index), time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> DateTime.from_unix!(mtime)
      {:error, _reason} -> nil
    end
  end

  defp changed_since(root, generated_at) do
    cutoff = DateTime.to_unix(generated_at)

    @source_globs
    |> Enum.flat_map(&Path.wildcard(Path.join(root, &1)))
    |> Enum.filter(&newer_than?(&1, cutoff))
  end

  defp newer_than?(path, cutoff) do
    case File.stat(path, time: :posix) do
      {:ok, %File.Stat{mtime: mtime}} -> mtime > cutoff
      # A path the glob listed but we cannot stat is not evidence of staleness.
      {:error, _reason} -> false
    end
  end
end
