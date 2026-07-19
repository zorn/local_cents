defmodule LocalCents.Tracking.BookStoreTest do
  # Async: each test writes into its own `:tmp_dir` (passed explicitly to every
  # BookStore call) rather than a shared `:books_dir` env, so tests never collide.
  use ExUnit.Case, async: true

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
    test "round-trips bytes through a .lcbook file", %{tmp_dir: dir} do
      id = BookStore.generate_id()
      assert :ok = BookStore.save(dir, id, "hello-bytes")

      assert BookStore.path(dir, id) == Path.join(dir, id <> ".lcbook")
      assert File.exists?(BookStore.path(dir, id))
      assert {:ok, "hello-bytes"} = BookStore.load(dir, id)
    end

    test "load/2 returns an error for an unknown id", %{tmp_dir: dir} do
      assert {:error, :enoent} = BookStore.load(dir, BookStore.generate_id())
    end

    test "overwriting is atomic and leaves no temporary file behind", %{tmp_dir: dir} do
      id = BookStore.generate_id()
      :ok = BookStore.save(dir, id, "first")
      :ok = BookStore.save(dir, id, "second")

      assert {:ok, "second"} = BookStore.load(dir, id)
      assert Path.wildcard(Path.join(dir, "*.tmp")) == []
    end

    test "a failed rename returns an error and leaves no temporary file behind", %{tmp_dir: dir} do
      # A directory at the final path makes the rename fail (can't rename a file
      # over a non-empty directory), exercising the error path after the temp write.
      id = BookStore.generate_id()
      File.mkdir_p!(Path.join(BookStore.path(dir, id), "occupied"))

      assert {:error, _reason} = BookStore.save(dir, id, "bytes")
      assert Path.wildcard(Path.join(dir, "*.tmp")) == []
    end
  end

  describe "list_ids/1" do
    test "starts empty and lists every saved book id", %{tmp_dir: dir} do
      assert BookStore.list_ids(dir) == []

      id1 = BookStore.generate_id()
      id2 = BookStore.generate_id()
      :ok = BookStore.save(dir, id1, "a")
      :ok = BookStore.save(dir, id2, "b")

      assert Enum.sort(BookStore.list_ids(dir)) == Enum.sort([id1, id2])
    end
  end

  describe "delete/2" do
    test "removes the file so it no longer enumerates", %{tmp_dir: dir} do
      id = BookStore.generate_id()
      :ok = BookStore.save(dir, id, "bytes")
      assert id in BookStore.list_ids(dir)

      assert :ok = BookStore.delete(dir, id)
      refute File.exists?(BookStore.path(dir, id))
      refute id in BookStore.list_ids(dir)
    end
  end
end
