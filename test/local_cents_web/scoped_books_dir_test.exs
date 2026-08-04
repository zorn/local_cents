defmodule LocalCentsWeb.ScopedBooksDirTest do
  @moduledoc """
  Guards the one claim the whole suite's `async: true` rests on: that a books
  directory claimed by a test process is the directory a LiveView mounted *by that
  test* writes to and reads from.

  The feature test modules all depend on this working, but none of them says so —
  they would each still pass if the directory resolved to the shared application-env
  default, right up until two of them ran at once. This module makes the claim
  explicit and fails loudly if the seam in `LocalCents.ProcessConfig` is removed.
  """

  use LocalCentsWeb.FeatureCase, async: true

  alias LocalCents.ProcessConfig
  alias LocalCents.Tracking

  @moduletag :tmp_dir

  setup ~M{tmp_dir} do
    ProcessConfig.put(:books_dir, tmp_dir)
    :ok
  end

  test "an ambient read in the test process resolves the claimed directory", ~M{tmp_dir} do
    # Guards against passing vacuously: the claimed directory has to be somewhere the
    # application env is *not* pointing, or this proves nothing.
    refute tmp_dir == Application.get_env(:local_cents, :books_dir)

    {:ok, _} = Tracking.create_book("Family Expenses")

    assert [%Tracking.Book{name: "Family Expenses"}] = Tracking.list_books()
    assert Path.wildcard(Path.join(tmp_dir, "*.lcbook")) != []
  end

  test "a LiveView mounted by the test resolves the same directory", ~M{conn, tmp_dir} do
    {:ok, _} = Tracking.create_book("Family Expenses")

    conn
    |> visit(~p"/library")
    |> assert_has("#books", text: "Family Expenses")

    # A Book created *through* the connected window lands in the claimed directory
    # too, which is the direction that only works if the LiveView process — not just
    # the test process — resolves it.
    assert length(Path.wildcard(Path.join(tmp_dir, "*.lcbook"))) == 1
  end
end
