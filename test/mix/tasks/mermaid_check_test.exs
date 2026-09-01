defmodule Mix.Tasks.Mermaid.CheckTest do
  use ExUnit.Case, async: false

  # The task shells out to `git` in the process working directory, so each test
  # runs inside its own throwaway repo rather than the project checkout.
  @moduletag :tmp_dir

  setup do
    shell = Mix.shell()
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(shell) end)
    :ok
  end

  describe "run/1" do
    test "skips a tracked file deleted from the working tree", %{tmp_dir: tmp_dir} do
      File.cd!(tmp_dir, fn ->
        {_, 0} = System.cmd("git", ["init", "-q"], env: [])
        File.write!("notes.md", "# Notes\n\nNo diagrams here.\n")
        {_, 0} = System.cmd("git", ["add", "notes.md"], env: [])
        # `git ls-files` still reports the file from the index, but the working
        # tree copy is gone — the exact state #188 crashed on.
        File.rm!("notes.md")

        Mix.Tasks.Mermaid.Check.run([])
      end)

      assert_received {:mix_shell, :info, ["No Mermaid diagrams found."]}
    end
  end
end
