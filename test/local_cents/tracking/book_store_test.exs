defmodule LocalCents.Tracking.BookStoreTest do
  # Not async: uses a temporary books directory via the global :books_dir env.
  use ExUnit.Case, async: false

  import LocalCents.BooksDirHelper

  alias LocalCents.Tracking.BookStore

  setup :with_temp_books_dir

  describe "generate_id/0" do
    test "returns distinct UUID-shaped strings" do
      id = BookStore.generate_id()
      assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
      refute id == BookStore.generate_id()
    end
  end

  describe "save/2, load/1, path/1" do
    test "round-trips bytes through a .lcbook file", %{books_dir: dir} do
      id = BookStore.generate_id()
      assert :ok = BookStore.save(id, "hello-bytes")

      assert BookStore.path(id) == Path.join(dir, id <> ".lcbook")
      assert File.exists?(BookStore.path(id))
      assert {:ok, "hello-bytes"} = BookStore.load(id)
    end

    test "load/1 returns an error for an unknown id" do
      assert {:error, :enoent} = BookStore.load(BookStore.generate_id())
    end
  end

  describe "list_ids/0" do
    test "starts empty and lists every saved book id" do
      assert BookStore.list_ids() == []

      id1 = BookStore.generate_id()
      id2 = BookStore.generate_id()
      :ok = BookStore.save(id1, "a")
      :ok = BookStore.save(id2, "b")

      assert Enum.sort(BookStore.list_ids()) == Enum.sort([id1, id2])
    end
  end

  describe "delete/1" do
    test "removes the file so it no longer enumerates" do
      id = BookStore.generate_id()
      :ok = BookStore.save(id, "bytes")
      assert id in BookStore.list_ids()

      assert :ok = BookStore.delete(id)
      refute File.exists?(BookStore.path(id))
      refute id in BookStore.list_ids()
    end
  end
end
