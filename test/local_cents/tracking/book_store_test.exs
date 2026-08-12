defmodule LocalCents.Tracking.BookStoreTest do
  # Async: each test writes into its own `:tmp_dir` (passed explicitly to every
  # BookStore call) rather than a shared `:books_dir` env, so tests never collide.
  use ExUnit.Case, async: true

  import TinyMaps

  alias LocalCents.Tracking.BookStore

  # ExUnit creates a unique temp directory per test (path includes the module and
  # test name) and exposes it as `context.tmp_dir` — already isolated for concurrent
  # runs, so it replaces the old global-env override helper.
  @moduletag :tmp_dir

  describe "generate_id/0" do
    test "returns distinct UUID-shaped strings" do
      id = BookStore.generate_id()
      assert id =~ ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/
      refute id == BookStore.generate_id()
    end
  end

  describe "save/3, load/2, path/2" do
    test "round-trips bytes through a .lcbook file", ~M{tmp_dir} do
      id = BookStore.generate_id()
      assert :ok = BookStore.save(tmp_dir, id, "hello-bytes")

      assert BookStore.path(tmp_dir, id) == Path.join(tmp_dir, id <> ".lcbook")
      assert File.exists?(BookStore.path(tmp_dir, id))
      assert {:ok, "hello-bytes"} = BookStore.load(tmp_dir, id)
    end

    test "load/2 returns an error for an unknown id", ~M{tmp_dir} do
      assert {:error, :enoent} = BookStore.load(tmp_dir, BookStore.generate_id())
    end

    test "overwriting is atomic and leaves no temporary file behind", ~M{tmp_dir} do
      id = BookStore.generate_id()
      :ok = BookStore.save(tmp_dir, id, "first")
      :ok = BookStore.save(tmp_dir, id, "second")

      assert {:ok, "second"} = BookStore.load(tmp_dir, id)
      assert Path.wildcard(Path.join(tmp_dir, "*.tmp")) == []
    end

    test "a failed rename returns an error and leaves no temporary file behind", ~M{tmp_dir} do
      # A directory at the final path makes the rename fail (can't rename a file
      # over a non-empty directory), exercising the error path after the temp write.
      id = BookStore.generate_id()
      File.mkdir_p!(Path.join(BookStore.path(tmp_dir, id), "occupied"))

      assert {:error, _reason} = BookStore.save(tmp_dir, id, "bytes")
      assert Path.wildcard(Path.join(tmp_dir, "*.tmp")) == []
    end
  end

  describe "list_ids/1" do
    test "starts empty and lists every saved book id", ~M{tmp_dir} do
      assert BookStore.list_ids(tmp_dir) == []

      id1 = BookStore.generate_id()
      id2 = BookStore.generate_id()
      :ok = BookStore.save(tmp_dir, id1, "a")
      :ok = BookStore.save(tmp_dir, id2, "b")

      assert Enum.sort(BookStore.list_ids(tmp_dir)) == Enum.sort([id1, id2])
    end
  end

  describe "delete/2" do
    test "removes the file so it no longer enumerates", ~M{tmp_dir} do
      id = BookStore.generate_id()
      :ok = BookStore.save(tmp_dir, id, "bytes")
      assert id in BookStore.list_ids(tmp_dir)

      assert :ok = BookStore.delete(tmp_dir, id)
      refute File.exists?(BookStore.path(tmp_dir, id))
      refute id in BookStore.list_ids(tmp_dir)
    end
  end
end
