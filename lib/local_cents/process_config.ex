defmodule LocalCents.ProcessConfig do
  @moduledoc """
  Provides get and put logic across a `ProcessTree` allowing for ownership of resources
  by test process that normally in production would be global.

  ## Problem Statement

  We value a through and fast test suite as it helps us work efficiently. All
  test modules of the project need to prioritize the `async: true` option
  however this is not always an easy thing to enable depending on what part of
  the system is under test.

  For simple pure functions, we get this mostly for free.

      def valid_base64?(string) do
        match?({:ok, _}, Base.decode64(string))
      end

  For functions that will rely on a dynamic value that could be considered
  global state we can provide options (via `opts` keyword lists) or other
  arguments to allow a call site to override. This can be helpful to override
  the concept of `now` in a test or provide a test-unique directory to make sure
  this test module does not interfere with the work going on in another test
  module (while a production configuration would likely used a shared space).

       def quick_add_expense(description, cost, opts \\ []) do
          now = Keyword.get(opts, :now, DateTime.utc_now())
          dir = Keyword.get(opts, :dir, BookStore.default_dir())
          ...
       end

  For databases that want isolated state during async test runs we lean on the [database sandboxing provided by Ecto](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html).

  If you need to override an external dependency you can lean on [Mox](https://hex.pm/packages/mox), and if you are looking to override an internal dependency you can lean on [Mimic](https://hex.pm/packages/mimic).

  For LocalCents we are building up a [rich OTP GenServer hierarchy](file:///Users/zorn/ProjectRepos/local_cents/doc/book-runtime-architecture.html#supervision-tree) and that tree has singleton-like assumptions about where books are stored on disk, the `:books_dir`. Normally inside of a LiveView test module you would have no obvious way to configure the `:books_dir` so what we do is



  Some settings have no caller in a position to inject them: `default_dir/0` runs
  deep inside `LocalCents.Tracking` with no directory in hand, and a LiveView asks
  whether demo seeding is on from a process the test never touches. Read straight
  from the application env, each of those settings is one global cell — so a test
  that wants its own value has to mutate that cell, and every module that does so
  must run `async: false`.

  This module is the seam that removes that constraint. In production `get/2` is
  `Application.get_env/3` and nothing more. In the test build it first looks the
  key up in the calling process's tree — the process dictionaries of the caller,
  its `$callers`, and its ancestors — and only falls back to the application env
  when no process in that tree has claimed a value. A test claims one with
  `put/2`, and every process it goes on to spawn (a `Task`, the LiveView that
  `Phoenix.LiveViewTest` joins on its behalf) resolves to that value while a
  concurrent test's tree resolves to its own.

  The result is that the setting stays global in production and stops being global
  in the suite, which is what lets every test module run `async: true`. See
  [Async testing](async-testing.html) for the full strategy, and for what to do
  when you add a setting that needs this treatment.

      # In a test's setup:
      ProcessConfig.put(:books_dir, dir)

      # Anywhere the test reaches, directly or through a LiveView:
      ProcessConfig.get(:books_dir)
      #=> the dir this test claimed, not the one a concurrent test claimed

  ## Prefer an argument when there is one

  This is the fallback, not the goal. Where a caller can pass the value down —
  the way `LocalCents.Tracking` accepts `:books_dir` and threads it into
  `LocalCents.Tracking.BookServer` — do that instead: an argument is visible in
  the signature, needs no lookup, and cannot resolve to the wrong value. Reach for
  `ProcessConfig` only for the ambient reads that have no such path.
  """

  use Boundary, top_level?: true, deps: []

  # This boolean informs the function logic below if it should look to the process tree for a value.
  # Only the `:test` environment should configure this to to `true`.
  @scoped_to_process_tree Application.compile_env(
                            :local_cents,
                            [LocalCents.ProcessConfig, :scoped_to_process_tree],
                            false
                          )

  @doc """
  Returns the value of the `:local_cents` setting `key`.

  Resolves the calling process's tree first in the test build (see the moduledoc),
  then the application env, then `default`.
  """
  @spec get(key :: atom(), default :: term()) :: term()
  def get(key, default \\ nil) when is_atom(key) do
    resolve(key, Application.get_env(:local_cents, key, default))
  end

  if @scoped_to_process_tree do
    # `cache: false` because `ProcessTree` otherwise memoizes the resolved value into
    # the dictionary of whichever process asked. That is a win for a long-lived
    # process and a hazard here: an app-supervised process that resolved once would
    # keep answering with the first test's value for the rest of the run.
    defp resolve(key, ambient) do
      ProcessTree.get({__MODULE__, key}, cache: false, default: ambient)
    end

    @doc """
    Claims `value` for `key` in the calling process and everything it spawns.

    A `nil` value is **not** a claim. The tree walk returns the first *non-nil*
    value it finds, so `put(key, nil)` is indistinguishable from never having
    called this and `get/2` falls through to the application env. `false` is a
    real value and does round-trip. There is no way to claim "no value at all";
    claim a sentinel instead if a test needs one.

    Defined in the test build only — production has no reason to rebind a setting,
    and the compile-time switch means a call to it outside the suite fails to
    compile rather than silently doing nothing.
    """
    @spec put(key :: atom(), value :: term()) :: :ok
    def put(key, value) when is_atom(key) do
      Process.put({__MODULE__, key}, value)
      :ok
    end
  else
    defp resolve(_key, ambient), do: ambient
  end
end
