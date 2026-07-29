defmodule LocalCentsWeb.DevDocsTest do
  use ExUnit.Case, async: true

  # The `~M` sigil for map shorthand, e.g. `~M{root}` for `%{root: root}`.
  import TinyMaps

  alias LocalCentsWeb.DevDocs

  # A stand-in project directory: an optional generated `doc/index.html` and a source
  # file, each with the modification time the case under test needs. Times are set
  # explicitly rather than by writing in sequence, so the assertions do not depend on
  # the filesystem's timestamp granularity.
  setup do
    root = Path.join(System.tmp_dir!(), "dev_docs_test_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(root, "lib/local_cents_web"))
    File.mkdir_p!(Path.join(root, "doc"))
    on_exit(fn -> File.rm_rf!(root) end)

    {:ok, root: root}
  end

  defp write(root, path, at) do
    full = Path.join(root, path)
    File.write!(full, "contents")
    File.touch!(full, at)
    full
  end

  @earlier 1_700_000_000
  @later 1_700_000_100

  describe "status/1" do
    test "is missing when the docs have never been generated", ~M{root} do
      write(root, "lib/local_cents_web/thing.ex", @earlier)

      assert DevDocs.status(root) == :missing
    end

    test "is fresh when nothing has changed since generation", ~M{root} do
      write(root, "lib/local_cents_web/thing.ex", @earlier)
      write(root, "doc/index.html", @later)

      assert {:fresh, generated_at} = DevDocs.status(root)
      assert DateTime.to_unix(generated_at) == @later
    end

    test "is stale when a source file is newer than the docs", ~M{root} do
      write(root, "doc/index.html", @earlier)
      changed = write(root, "lib/local_cents_web/thing.ex", @later)

      assert {:stale, generated_at, [^changed]} = DevDocs.status(root)
      assert DateTime.to_unix(generated_at) == @earlier
    end

    test "notices a changed prose doc, not only source", ~M{root} do
      File.mkdir_p!(Path.join(root, "docs/adr"))
      write(root, "doc/index.html", @earlier)
      changed = write(root, "docs/adr/0001-a-decision.md", @later)

      assert {:stale, _generated_at, [^changed]} = DevDocs.status(root)
    end

    test "notices a changed mix.exs, which carries the docs configuration", ~M{root} do
      write(root, "doc/index.html", @earlier)
      changed = write(root, "mix.exs", @later)

      assert {:stale, _generated_at, [^changed]} = DevDocs.status(root)
    end

    # The generated docs live under `doc/`, which would otherwise make every generation
    # instantly stale by its own output.
    test "the generated output does not count as a changed source", ~M{root} do
      write(root, "doc/index.html", @earlier)
      write(root, "doc/api-reference.html", @later)

      assert {:fresh, _generated_at} = DevDocs.status(root)
    end
  end

  describe "index_path/0" do
    test "points at where the endpoint serves the generated docs" do
      assert DevDocs.index_path() == "/doc/index.html"
    end
  end
end
