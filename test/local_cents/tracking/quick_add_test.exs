defmodule LocalCents.Tracking.QuickAddTest do
  use ExUnit.Case, async: true

  alias LocalCents.Tracking.QuickAdd

  describe "parse/1" do
    test "reads a trailing amount as the cost and the rest as the description" do
      assert QuickAdd.parse("coffee 4.75") == {:ok, %{description: "coffee", cost: "4.75"}}
    end

    test "keeps a multi-word description intact, only peeling the trailing amount" do
      assert QuickAdd.parse("2 coffees 4.75") == {:ok, %{description: "2 coffees", cost: "4.75"}}
    end

    test "a line with no trailing amount is all description, cost absent" do
      assert QuickAdd.parse("coffee") == {:ok, %{description: "coffee", cost: nil}}
    end

    test "a lone amount echoes itself as the description so nothing is lost" do
      assert QuickAdd.parse("4.75") == {:ok, %{description: "4.75", cost: "4.75"}}
    end

    test "an integer amount is recognized" do
      assert QuickAdd.parse("bus 3") == {:ok, %{description: "bus", cost: "3"}}
    end

    test "trims surrounding whitespace" do
      assert QuickAdd.parse("  coffee 4.75  ") == {:ok, %{description: "coffee", cost: "4.75"}}
    end

    test "blank or whitespace-only input is a no-op" do
      assert QuickAdd.parse("") == :blank
      assert QuickAdd.parse("   ") == :blank
    end

    # No `$`/comma/sign/dangling-dot cleverness: an unrecognized trailing token is
    # left as part of the description and the cost stays absent.
    test "a dollar-prefixed token is not an amount" do
      assert QuickAdd.parse("coffee $4.75") == {:ok, %{description: "coffee $4.75", cost: nil}}
    end

    test "a comma-grouped token is not an amount" do
      assert QuickAdd.parse("rent 1,200") == {:ok, %{description: "rent 1,200", cost: nil}}
    end

    test "a signed token is not an amount" do
      assert QuickAdd.parse("refund -5") == {:ok, %{description: "refund -5", cost: nil}}
    end

    test "dangling-dot tokens are not amounts" do
      assert QuickAdd.parse("coffee 4.") == {:ok, %{description: "coffee 4.", cost: nil}}
      assert QuickAdd.parse("coffee .75") == {:ok, %{description: "coffee .75", cost: nil}}
    end
  end
end
