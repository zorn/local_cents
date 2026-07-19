defmodule LocalCents.Tracking.MonthTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.Month

  describe "new/2" do
    test "builds a Month from a year and a month number" do
      assert %Month{year: 2026, month: 3} = Month.new(2026, 3)
    end

    test "rejects a month number outside 1..12" do
      assert_raise ArgumentError, fn -> Month.new(2026, 0) end
      assert_raise ArgumentError, fn -> Month.new(2026, 13) end
    end
  end

  describe "from_date/1" do
    test "derives the calendar year and month, dropping the day" do
      assert Month.from_date(~D[2026-03-17]) == Month.new(2026, 3)
      assert Month.from_date(~D[2026-12-01]) == Month.new(2026, 12)
    end
  end

  describe "compare/2" do
    test "orders by year, then month" do
      assert Month.compare(Month.new(2025, 12), Month.new(2026, 1)) == :lt
      assert Month.compare(Month.new(2026, 3), Month.new(2026, 3)) == :eq
      assert Month.compare(Month.new(2026, 4), Month.new(2026, 3)) == :gt
    end

    test "is usable as an Enum.sort/2 comparator" do
      months = [Month.new(2026, 2), Month.new(2025, 11), Month.new(2026, 1)]

      assert Enum.sort(months, Month) == [
               Month.new(2025, 11),
               Month.new(2026, 1),
               Month.new(2026, 2)
             ]
    end
  end

  describe "next/1" do
    test "advances within a year" do
      assert Month.next(Month.new(2026, 3)) == Month.new(2026, 4)
    end

    test "rolls over the year boundary" do
      assert Month.next(Month.new(2026, 12)) == Month.new(2027, 1)
    end
  end

  describe "range/2" do
    test "returns a single month when earliest equals latest" do
      m = Month.new(2026, 3)
      assert Month.range(m, m) == [m]
    end

    test "fills every month contiguously, inclusive of both ends" do
      assert Month.range(Month.new(2025, 11), Month.new(2026, 2)) == [
               Month.new(2025, 11),
               Month.new(2025, 12),
               Month.new(2026, 1),
               Month.new(2026, 2)
             ]
    end

    test "raises when earliest is after latest" do
      assert_raise ArgumentError, fn ->
        Month.range(Month.new(2026, 5), Month.new(2026, 1))
      end
    end
  end

  describe "to_string/1" do
    test "renders as a zero-padded YYYY-MM string" do
      assert Month.to_string(Month.new(2026, 3)) == "2026-03"
      assert Month.to_string(Month.new(2026, 12)) == "2026-12"
    end

    test "backs the String.Chars protocol" do
      assert "#{Month.new(2026, 3)}" == "2026-03"
    end
  end
end
