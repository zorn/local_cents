defmodule LocalCents.Tracking.QuickAdd do
  @moduledoc """
  Parses a single quick-add line into `Expense` attributes.

  Quick-add is the deliberately minimal capture path: the user types one line, an
  optional trailing amount is the Cost and everything before it is the Description
  (dated today, never a Category). This module is that parser and nothing more — the
  `LocalCents.Tracking.quick_add_expense/3` context function feeds the result to the
  same `LocalCents.Tracking.Expense` changeset that the full editor uses, so validation
  and persistence stay on one path.

  ## The grammar

  The line is split on whitespace and only the **last token** is examined:

    * If the last token is a plain non-negative decimal (`4.75`, `12`, `0`) it is the
      Cost, and the tokens before it are the Description. A lone amount (`4.75` with no
      description) echoes itself as the Description so the amount is never dropped.
    * Otherwise the whole line is the Description and the Cost is absent (`nil`).
    * Blank or whitespace-only input is `:blank` — the caller creates nothing.

  Recognizing an amount is intentionally strict: `^\\d+(\\.\\d+)?$` and no more. A `$`
  prefix, comma grouping (`1,200`), a sign (`-5`), or a dangling dot (`4.` / `.75`) is
  *not* an amount — that token stays in the Description and the Cost is left absent.
  This is the "deliberately dumb, no cleverness" capture path from the Expenses section
  of the MVP proposal (`docs/proposals/mvp.md`) and
  [issue #64](https://github.com/zorn/local_cents/issues/64): no relative dates, no
  currency symbols, no draft handling. Because the recognized token is always a bare
  decimal, it casts cleanly in the changeset, so quick-add can never surface a
  validation error — a missing amount is simply absent, honest per
  [ADR 0008](0008-mvp-expense-shape.html).
  """

  # Anchored on both ends so a trailing token is an amount only if it is *entirely* a
  # plain decimal; the non-amount cases and the rationale live in the moduledoc.
  @amount ~r/^\d+(\.\d+)?$/

  @typedoc """
  The parsed attributes: a Description and a Cost (a decimal string, or `nil` when the
  line carried no trailing amount).
  """
  @type attrs() :: %{description: String.t(), cost: String.t() | nil}

  @doc """
  Parses `line` into Expense attributes, or `:blank` when there is nothing to add.

  See the moduledoc for the grammar. The returned `:cost` is a raw decimal string (or
  `nil`) handed straight to the `LocalCents.Tracking.Expense` changeset, which casts it
  to a `Decimal`.
  """
  @spec parse(String.t()) :: {:ok, attrs()} | :blank
  def parse(line) when is_binary(line) do
    trimmed = String.trim(line)

    case String.split(trimmed) do
      [] -> :blank
      tokens -> {:ok, attrs(tokens, trimmed)}
    end
  end

  defp attrs(tokens, trimmed) do
    last = List.last(tokens)

    if Regex.match?(@amount, last) do
      %{description: description(tokens, last), cost: last}
    else
      %{description: trimmed, cost: nil}
    end
  end

  # Peel the trailing amount off; a lone amount leaves no description, so reuse the
  # amount text rather than saving a blank one.
  defp description(tokens, amount) do
    case tokens |> Enum.drop(-1) |> Enum.join(" ") do
      "" -> amount
      rest -> rest
    end
  end
end
