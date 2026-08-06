defmodule LocalCents.BooksDirHelper do
  @moduledoc """
  Claims the test's `:tmp_dir` as its books directory, so
  `LocalCents.Tracking.BookStore.default_dir/0` resolves to it everywhere that
  test reaches — including the LiveView process `Phoenix.LiveViewTest` mounts on
  its behalf.

  This is for the **LiveView feature tests**, where the directory can't be
  injected as an argument: the LiveView calls the dir-free `LocalCents.Tracking`
  API in its own process. The claim is scoped to the test's process tree via
  `LocalCents.ProcessConfig` rather than written to a shared application env,
  which is what lets those modules run `async: true` alongside each other. See
  [Async testing](async-testing.html).

  Unit and context tests use the same `:tmp_dir`, but pass it explicitly to the
  `LocalCents.Tracking`/`BookStore` functions instead of claiming it, which is
  cheaper still (see `docs/research/avoiding-async-false-tests.md`).

  Tag the module and use it as a setup callback:

      @moduletag :tmp_dir

      setup :with_async_books_dir
  """

  # Its own top-level boundary rather than a member of the `LocalCents` core: this is
  # test-support scaffolding that happens to sit in the domain namespace, and the core
  # has no business gaining a dependency on `ProcessConfig` on its behalf.
  use Boundary, top_level?: true, deps: [LocalCents.ProcessConfig]

  alias LocalCents.ProcessConfig

  # Nothing to tear down. The claim lives in the test process's dictionary and dies
  # with it, and ExUnit empties the `:tmp_dir` *before* each run of the test rather
  # than after, so no removal can race the late persist of a `BookServer` that is
  # supervised by the application and reaps `viewer_grace_ms` after its last viewer
  # goes. The directory is left behind on purpose — it is there to read when a test
  # fails. Leaks that matter are caught loudly elsewhere: `test/test_helper.exs`
  # empties the shared fallback directory per run.
  #
  # Matching on `:tmp_dir` means a module that forgets `@moduletag :tmp_dir` fails
  # here rather than quietly claiming a directory nobody prepared. The second clause
  # exists only to say so in one sentence: the `FunctionClauseError` it replaces
  # dumps the whole context — `conn` struct included — and buries the one line that
  # matters.
  @spec with_async_books_dir(map()) :: :ok
  def with_async_books_dir(%{tmp_dir: tmp_dir}) do
    ProcessConfig.put(:books_dir, tmp_dir)
  end

  def with_async_books_dir(context) do
    raise """
    #{inspect(context[:module])} calls `setup :with_async_books_dir` but is not tagged \
    for a temporary directory, so there is no `:tmp_dir` in the test context to claim.

    Add the tag next to the setup callback:

        @moduletag :tmp_dir

        setup :with_async_books_dir
    """
  end
end
