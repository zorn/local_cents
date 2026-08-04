defmodule LocalCents.BooksDirHelper do
  @moduledoc """
  Claims a fresh temporary books directory for the running test, so
  `LocalCents.Tracking.BookStore.default_dir/0` resolves to it everywhere that
  test reaches — including the LiveView process `Phoenix.LiveViewTest` mounts on
  its behalf.

  This is for the **LiveView feature tests**, where the directory can't be
  injected as an argument: the LiveView calls the dir-free `LocalCents.Tracking`
  API in its own process. The claim is scoped to the test's process tree via
  `LocalCents.ProcessConfig` rather than written to a shared application env,
  which is what lets those modules run `async: true` alongside each other. See
  [Async testing](async-testing.html).

  Unit and context tests do *not* use this: they tag `@moduletag :tmp_dir` and pass
  the directory explicitly to the `LocalCents.Tracking`/`BookStore` functions, which
  is cheaper still (see `docs/research/avoiding-async-false-tests.md`).

  Use it as a setup callback:

      setup :with_temp_books_dir
  """

  # Its own top-level boundary rather than a member of the `LocalCents` core: this is
  # test-support scaffolding that happens to sit in the domain namespace, and the core
  # has no business gaining a dependency on `ProcessConfig` on its behalf.
  use Boundary, top_level?: true, deps: [LocalCents.ProcessConfig]

  alias LocalCents.ProcessConfig

  @spec with_temp_books_dir(map()) :: {:ok, keyword()}
  def with_temp_books_dir(_context) do
    dir = Path.join(System.tmp_dir!(), "lc_books_#{System.unique_integer([:positive])}")
    ProcessConfig.put(:books_dir, dir)

    # The claim itself needs no teardown — it lives in the test process's dictionary
    # and dies with it. Only the directory outlives the test, and `on_exit` runs in a
    # separate process, so this closes over the path rather than resolving it again.
    #
    # `rm_rf/1` rather than `rm_rf!/1` on purpose: a `BookServer` is supervised by the
    # application, not the test, and reaps `viewer_grace_ms` (50ms here) after its last
    # viewer goes, so a late persist can race this removal. A leftover temp directory
    # is a far better outcome than an intermittently red suite. Leaks that matter are
    # caught loudly elsewhere — `test/test_helper.exs` empties the shared fallback
    # directory per run.
    ExUnit.Callbacks.on_exit(fn -> File.rm_rf(dir) end)

    {:ok, books_dir: dir}
  end
end
