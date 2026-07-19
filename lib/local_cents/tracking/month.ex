defmodule LocalCents.Tracking.Month do
  @moduledoc """
  A calendar year-and-month (e.g. `2026-03`) — the time bucket a `Report` groups
  spending into (see [ADR 0020](0020-bounded-time-series-in-review.html)).

  A Month is a *calendar span*, not a rolling window or a billing cycle, and unlike
  the `LocalCents.Tracking.Expense` `date` it comes from it carries no day, no
  time-of-day, and no timezone (see
  [ADR 0015](0015-expense-identity-and-date-encoding.html)). Modeling it as its own
  value — rather than reusing a `Date` pinned to the first of the month — is what
  keeps "a Month" from being mistaken for "a day" and gives the Report's column
  logic (ordering and contiguous-range fill) one authoritative home.

  Values are compared with `compare/2`, so a Month works directly as an
  `Enum.sort/2` comparator (`Enum.sort(months, Month)`) and as a map key. `range/2`
  produces the contiguous, gap-filled column axis a Report spans; `next/1` steps one
  month forward, rolling the year. `to_string/1` renders the canonical `YYYY-MM`
  form, also exposed through the `String.Chars` protocol.
  """

  # This module defines its own `to_string/1` for the canonical `YYYY-MM` rendering;
  # shadow the auto-imported `Kernel.to_string/1` so the two don't collide.
  import Kernel, except: [to_string: 1]

  @enforce_keys [:year, :month]
  defstruct [:year, :month]

  @typedoc "A calendar month number, 1 (January) through 12 (December)."
  @type month_number() :: 1..12

  @type t() :: %__MODULE__{year: integer(), month: month_number()}

  @doc """
  Builds a Month from a `year` and a `month` number (1–12).

  Raises `ArgumentError` for a non-integer year or a month outside 1..12 — a Month
  is a real calendar position, not an arbitrary pair of integers.
  """
  @spec new(year :: integer(), month :: month_number()) :: t()
  def new(year, month) when is_integer(year) and is_integer(month) and month in 1..12 do
    %__MODULE__{year: year, month: month}
  end

  # Distinct clauses so a bad year and a bad month each report the argument actually
  # at fault, rather than a single message that blames the month for either.
  def new(year, _month) when not is_integer(year) do
    raise ArgumentError, "year must be an integer, got: #{inspect(year)}"
  end

  def new(_year, month) do
    raise ArgumentError, "month must be in 1..12, got: #{inspect(month)}"
  end

  @doc """
  Derives the Month a `Date` falls in, dropping the day.
  """
  @spec from_date(Date.t()) :: t()
  def from_date(%Date{year: year, month: month}), do: new(year, month)

  @doc """
  Compares two Months by year then month, returning `:lt`, `:eq`, or `:gt`.

  Matches the shape `Enum.sort/2` expects, so `Enum.sort(months, #{inspect(__MODULE__)})`
  orders a list of Months chronologically.
  """
  @spec compare(a :: t(), b :: t()) :: :lt | :eq | :gt
  def compare(%__MODULE__{} = a, %__MODULE__{} = b) do
    cond do
      key(a) < key(b) -> :lt
      key(a) > key(b) -> :gt
      true -> :eq
    end
  end

  @doc """
  Returns the Month one calendar month after `month`, rolling into the next year
  after December.
  """
  @spec next(t()) :: t()
  def next(%__MODULE__{year: year, month: 12}), do: new(year + 1, 1)
  def next(%__MODULE__{year: year, month: month}), do: new(year, month + 1)

  @doc """
  Returns every Month from `earliest` to `latest`, inclusive and contiguous — the
  gap-filled column axis a `Report` spans, so a Month with no spending still appears
  rather than collapsing.

  Raises `ArgumentError` if `earliest` is after `latest`.
  """
  @spec range(earliest :: t(), latest :: t()) :: [t(), ...]
  def range(%__MODULE__{} = earliest, %__MODULE__{} = latest) do
    case compare(earliest, latest) do
      :gt ->
        raise ArgumentError,
              "earliest #{to_string(earliest)} is after latest #{to_string(latest)}"

      _ ->
        earliest
        |> Stream.iterate(&next/1)
        |> Enum.take_while(&(compare(&1, latest) != :gt))
    end
  end

  @doc """
  Renders a Month as its canonical zero-padded `YYYY-MM` string.
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{year: year, month: month}) do
    "#{year}-#{String.pad_leading(Integer.to_string(month), 2, "0")}"
  end

  # A monotonic sort key so year always outranks month; the constant multiplier is
  # larger than any month number, so ordering by it is identical to year-then-month.
  defp key(%__MODULE__{year: year, month: month}), do: year * 100 + month

  defimpl String.Chars do
    defdelegate to_string(month), to: LocalCents.Tracking.Month
  end
end
