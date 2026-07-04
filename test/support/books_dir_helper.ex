defmodule LocalCents.BooksDirHelper do
  @moduledoc """
  Test helper that points `LocalCents.Tracking.BookStore` at a fresh temporary
  books directory for the duration of a test and cleans it up afterwards.

  Because it mutates the global `:books_dir` application env, test modules using it
  must run with `async: false`.

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
