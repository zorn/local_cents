defmodule LocalCents.BooksDirHelper do
  @moduledoc """
  Points `LocalCents.Tracking.BookStore.default_dir/0` at a fresh temporary books
  directory for the duration of a test and cleans it up afterwards, by overriding
  the `:books_dir` application env.

  This is for the **LiveView feature tests only**, where the directory can't be
  injected as an argument (the LiveView calls the dir-free `LocalCents.Tracking`
  API in its own process). Because it mutates a global env, those modules run with
  `async: false`.

  Unit and context tests do *not* use this: they tag `@moduletag :tmp_dir` and pass
  the directory explicitly to the `LocalCents.Tracking`/`BookStore` functions, which
  keeps them `async: true` (see `docs/research/avoiding-async-false-tests.md`).

  Use it as a setup callback:

      setup :with_temp_books_dir
  """

  @spec with_temp_books_dir(map()) :: {:ok, keyword()}
  def with_temp_books_dir(_context) do
    dir = Path.join(System.tmp_dir!(), "lc_books_#{System.unique_integer([:positive])}")
    previous = Application.get_env(:local_cents, :books_dir)
    Application.put_env(:local_cents, :books_dir, dir)

    ExUnit.Callbacks.on_exit(fn ->
      File.rm_rf(dir)
      Application.put_env(:local_cents, :books_dir, previous)
    end)

    {:ok, books_dir: dir}
  end
end
