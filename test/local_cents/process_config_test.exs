defmodule LocalCents.ProcessConfigTest do
  @moduledoc """
  Validated the logic of `LocalCents.ProcessConfig` for scoping configuration to
  a process tree, and ensuring that descendant processes see the value set by
  their ancestor.
  """

  use ExUnit.Case, async: true

  # `Task.async/1` is the subject here, not an oversight: `Task` is the only thing in
  # the standard library that writes `$callers`, so an unsupervised task is precisely
  # the propagation this module has to prove. Every task below is awaited, so the leak
  # the check guards against cannot occur.
  # credo:disable-for-this-file OeditusCredo.Check.Warning.UnmanagedTask

  alias LocalCents.ProcessConfig

  # A key no config file sets, so "unset" means unset rather than "whatever
  # config/test.exs happens to say today".
  @unset_key :process_config_test_unset

  describe "get/2 without a scoped value" do
    test "falls back to the application env" do
      assert ProcessConfig.get(:books_dir) ==
               Application.get_env(:local_cents, :books_dir)
    end

    test "returns the given default when the application env has no value" do
      assert ProcessConfig.get(@unset_key, :fallback) == :fallback
    end

    test "returns nil when there is neither a value nor a default" do
      # `assert … == nil`, not `refute`: the test below turns on `false` being a
      # value rather than an absence, so a falsy-only assertion would pass on the
      # exact confusion this module has to avoid.
      assert ProcessConfig.get(@unset_key) == nil
    end
  end

  describe "put/2" do
    test "scopes the value to the calling process" do
      ProcessConfig.put(@unset_key, "/scoped/dir")

      assert ProcessConfig.get(@unset_key) == "/scoped/dir"
    end

    test "takes precedence over the application env" do
      ProcessConfig.put(:books_dir, "/scoped/books")

      assert ProcessConfig.get(:books_dir) == "/scoped/books"
    end

    test "scopes a false value, which must not read as unset" do
      ProcessConfig.put(@unset_key, false)

      assert ProcessConfig.get(@unset_key, true) == false
    end

    test "keeps concurrent trees from resolving each other's value" do
      # The property the whole suite's `async: true` rests on, in miniature: each
      # `Task` stands in for a test process claiming its own value, and the child it
      # spawns stands in for the LiveView that test drives.
      claim_and_resolve = fn value ->
        Task.async(fn ->
          ProcessConfig.put(@unset_key, value)
          Task.await(Task.async(fn -> ProcessConfig.get(@unset_key, :none) end))
        end)
      end

      a = claim_and_resolve.("/tree/a")
      b = claim_and_resolve.("/tree/b")

      assert Task.await(a) == "/tree/a"
      assert Task.await(b) == "/tree/b"
    end
  end

  describe "get/2 from a descendant process" do
    test "resolves the value scoped by the calling process" do
      ProcessConfig.put(@unset_key, "/scoped/dir")

      task = Task.async(fn -> ProcessConfig.get(@unset_key) end)

      assert Task.await(task) == "/scoped/dir"
    end

    test "resolves through a nested descendant" do
      ProcessConfig.put(@unset_key, "/scoped/dir")

      task = Task.async(fn -> Task.await(Task.async(fn -> ProcessConfig.get(@unset_key) end)) end)

      assert Task.await(task) == "/scoped/dir"
    end

    test "resolves from a process supervised by the test" do
      ProcessConfig.put(@unset_key, "/scoped/dir")
      test_pid = self()

      start_supervised!(
        {Task, fn -> send(test_pid, {:resolved, ProcessConfig.get(@unset_key, :none)}) end}
      )

      assert_receive {:resolved, "/scoped/dir"}
    end
  end
end
