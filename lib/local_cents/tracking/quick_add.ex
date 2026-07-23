defmodule LocalCents.Tracking.QuickAdd do
  @moduledoc """
  Parses a single quick-add line into the fields of an `Expense`.

  Quick-add is the deliberately minimal capture path: the user types one line, an
  optional trailing amount is the Cost and everything before it is the Description
  (dated today, never a Category). This module is that parser and nothing more — the
  `LocalCents.Tracking.quick_add_expense/3` context function feeds the result to the
  same `LocalCents.Tracking.Expense` changeset that the full editor uses, so validation
  and persistence stay on one path.

  It is the "deliberately dumb, no cleverness" capture path from the Expenses section of
  the MVP proposal (`docs/proposals/mvp.md`) and
  [issue #64](https://github.com/zorn/local_cents/issues/64): no relative dates, no
  currency symbols, no draft handling. Because a recognized amount is always a bare
  decimal, it casts cleanly in the changeset, so quick-add can never surface a
  validation error — a missing amount is simply absent, honest per
  [ADR 0008](0008-mvp-expense-shape.html). See `parse/1` for the grammar.
  """

  # Anchored on both ends so a trailing token is an amount only if it is *entirely* a
  # plain decimal; the recognized/rejected cases are documented on `parse/1`.
  @amount ~r/^\d+(\.\d+)?$/

  @typedoc """
  A parsed line: the Description and the Cost (a decimal string, or `nil` when the line
  carried no trailing amount).
  """
  @type parsed() :: %{description: String.t(), cost: String.t() | nil}

  @doc """
  Parses `line` into the Description and Cost of an Expense, or `:blank` when there is
  nothing to add.

  The line is split on whitespace and only the **last token** is examined:

    * If the last token is a plain non-negative decimal (`4.75`, `12`, `0`) it is the
      Cost, and the tokens before it are the Description. A lone amount echoes itself as
      the Description so the amount is never dropped.
    * Otherwise the whole line is the Description and the Cost is absent (`nil`).
    * Blank or whitespace-only input is `:blank` — the caller creates nothing.

  Recognizing an amount is intentionally strict. A `$` prefix, comma grouping (`1,200`),
  a sign (`-5`), or a dangling dot (`4.` / `.75`) is *not* an amount — that token stays
  in the Description and the Cost is left absent. The returned `:cost` is a raw decimal
  string (or `nil`) handed straight to the `LocalCents.Tracking.Expense` changeset,
  which casts it to a `Decimal`.

      iex> LocalCents.Tracking.QuickAdd.parse("coffee 4.75")
      {:ok, %{description: "coffee", cost: "4.75"}}

      iex> LocalCents.Tracking.QuickAdd.parse("2 coffees 4.75")
      {:ok, %{description: "2 coffees", cost: "4.75"}}

      iex> LocalCents.Tracking.QuickAdd.parse("coffee")
      {:ok, %{description: "coffee", cost: nil}}

      iex> LocalCents.Tracking.QuickAdd.parse("4.75")
      {:ok, %{description: "4.75", cost: "4.75"}}

      iex> LocalCents.Tracking.QuickAdd.parse("rent 1,200")
      {:ok, %{description: "rent 1,200", cost: nil}}

      iex> LocalCents.Tracking.QuickAdd.parse("   ")
      :blank
  """
  @spec parse(String.t()) :: {:ok, parsed()} | :blank
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
