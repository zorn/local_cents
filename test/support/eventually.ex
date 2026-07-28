defmodule LocalCents.Eventually do
  @moduledoc """
  A tiny polling helper for asserting on state that settles *asynchronously* — a
  process that reaps after a grace period, a `Phoenix.Presence` diff that propagates a
  beat after a `track`, a `Registry` entry that clears after a process dies.

  `wait_until/2` retries a predicate until it returns a truthy value (which it hands
  back) or the budget runs out (which fails the test). It is a bounded poll, not a
  fixed `sleep`: the call returns the instant the predicate is satisfied, so a test
  that settles quickly pays nothing, while a genuinely stuck one fails loudly rather
  than hanging. Reach for it instead of `Process.sleep/1` whenever a test waits on
  eventually-consistent runtime state.
  """

  import ExUnit.Assertions, only: [flunk: 1]

  @doc """
  Polls `fun` every 10ms until it returns a truthy value, which is returned. Fails the
  test if `timeout` (default 1s) elapses first.
  """
  @spec wait_until((-> any()), timeout :: non_neg_integer()) :: any()
  def wait_until(fun, timeout \\ 1_000) when is_function(fun, 0) do
    case fun.() do
      falsy when falsy in [false, nil] ->
        if timeout <= 0 do
          flunk("condition not met within the wait_until/2 timeout")
        else
          Process.sleep(10)
          wait_until(fun, timeout - 10)
        end

      truthy ->
        truthy
    end
  end
end
