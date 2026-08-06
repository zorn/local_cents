defmodule LocalCents.ProcessConfig do
  @moduledoc """
  Provides get and put logic across a `ProcessTree` allowing for ownership of resources
  and configurations by test process that normally in production would be global.

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

  For databases that want isolated state during async test runs we lean on the
  [database sandboxing provided by Ecto](https://ecto-sql.hexdocs.pm/Ecto.Adapters.SQL.Sandbox.html).

  If you need to override an external dependency you can lean on
  [Mox](https://hex.pm/packages/mox), and if you are looking to override an
  internal dependency you can lean on [Mimic](https://hex.pm/packages/mimic).

  For LocalCents we are building up a [rich OTP GenServer
  hierarchy](file:///Users/zorn/ProjectRepos/local_cents/doc/book-runtime-architecture.html#supervision-tree)
  and that tree has a global assumption about where books are stored on disk.
  The knowledge for where the books are stored comes from
  `BookStore.default_dir/0`. Normally inside of a LiveView test module you would
  have no obvious way to override this value, let alone override for an
  asynchronous running test module.

  To solve this we use the [`process_tree`
  library](https://process-tree.hexdocs.pm) which allows us to create a space of
  ownership per process. That could be ownership of a GenServer (we don't do
  this currently but might in the future) or ownership of a configuration value.
  We then update the logic to, inside of a test build, check the process tree
  for the value before falling back to the application env. This allows us to
  have a global value in production but a test-process-unique value in the test
  build.

  For a LiveView test module that wants to be `async: true` it looks like:

      @moduletag :tmp_dir
      setup :with_async_books_dir

  And the helper looks like:

      def with_async_books_dir(%{tmp_dir: tmp_dir}) do
        ProcessConfig.put(:books_dir, tmp_dir)
      end

  [ExUnit's `tmp_dir`](https://ex-unit.hexdocs.pm/1.20.3/ExUnit.Case.html#module-tmp-dir)
  is per test module name and automatically cleaned up after the test module
  finishes.

  Inside of `BookStore.default_dir/0` we use `ProcessConfig.get(:books_dir)` or
  fallback to the standard production value.

  This solution is heavily inspired by Andrea Leopardi's blog post on [Async
  tests in Elixir](https://andrealeopardi.com/posts/async-tests-in-elixir/) and
  I thank him for writing it up.
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
  Returns the value of `key` inside the `:local_cents` application settings, or `default` if none is set.

  Resolves via calling process's tree first in the test build, then the application env, then `default`.
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
    Records `value` for `key` in the calling process and everything it spawns.

    A `nil` value is **not** a valid value. The tree walk during `get/2` returns
    the first *non-nil* value it finds, so `put(key, nil)` is indistinguishable
    from never having called this and `get/2` falls through to the application
    env. `false` is a real value and does round-trip. There is no way to define
    "no value at all"; use a sentinel instead if a test needs one.

    Defined in the test build only — production has no reason to put a setting,
    and the compile-time switch means a call to it outside the test suite fails to
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
