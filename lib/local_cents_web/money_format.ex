defmodule LocalCentsWeb.MoneyFormat do
  @moduledoc """
  Renders a known monetary amount as user-facing text — the single place a `Decimal`
  cost becomes a `$X.XX` string.

  `dollars/1` renders a `Decimal` in the house `$X.XX` form (a leading `$`, always
  two decimal places). It deliberately handles only a *present* amount — how an
  *absent* cost reads is caller-specific and stays with the caller: the expense list
  shows a lone em dash, while the **Report** folds absence into a per-cell
  needs-amount count. Currency is US-dollar only for the MVP; a locale-aware display
  is a later concern.
  """

  @doc """
  Formats a `Decimal` amount as `$X.XX`, rounded to two places.
  """
  @spec dollars(Decimal.t()) :: String.t()
  def dollars(%Decimal{} = amount), do: "$" <> Decimal.to_string(Decimal.round(amount, 2))
end
