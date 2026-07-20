defmodule LocalCents.ModuleBoundariesDocTest do
  # Guards `docs/module-boundaries.md` against drift from the actual boundary
  # definitions. The doc's export table duplicates a fact that lives
  # authoritatively in each boundary's `exports:` option, and that copy has
  # silently fallen behind before (PR #140 / #151). This turns such drift into
  # a red build instead of a stale doc.
  use ExUnit.Case, async: true

  @doc_path "docs/module-boundaries.md"

  # Boundaries whose Exports cell in the table enumerates modules we want kept
  # in sync. `LocalCents`, `DemoSeeding`, and `Application` export nothing (the
  # cell is a dash) and `Storybook` has checks disabled, so they are not listed.
  @guarded_boundaries [LocalCents.Tracking]

  test "the boundary export table matches the real `exports:` for each boundary" do
    doc = File.read!(@doc_path)
    view = Boundary.Mix.View.build()

    for boundary <- @guarded_boundaries do
      documented = documented_exports(doc, boundary)
      actual = actual_exports(view, boundary)

      assert MapSet.size(documented) > 0,
             "Could not parse an Exports cell for #{inspect(boundary)} in #{@doc_path}. " <>
               "Did the table format change? This test parses the row whose Boundary " <>
               "cell is `#{inspect(boundary)}`."

      assert documented == actual, """
      #{@doc_path} lists different exports for #{inspect(boundary)} than its `exports:` option.

        documented in the table: #{inspect(Enum.sort(documented))}
        actual (exports:):       #{inspect(Enum.sort(actual))}
        missing from the doc:    #{inspect(actual |> MapSet.difference(documented) |> Enum.sort())}
        stale in the doc:        #{inspect(documented |> MapSet.difference(actual) |> Enum.sort())}

      Update the Exports cell in #{@doc_path} (or the boundary's `exports:`) so they agree.
      """
    end
  end

  # The short module names (e.g. "Book") backticked in the Exports cell of the
  # table row whose Boundary cell names `boundary`. Robust to table reflowing:
  # it keys off the row content, not line numbers, and only reads the third
  # `|`-delimited cell.
  defp documented_exports(doc, boundary) do
    short = boundary |> Module.split() |> Enum.join(".")

    row =
      doc
      |> String.split("\n", trim: true)
      |> Enum.filter(&String.starts_with?(&1, "|"))
      |> Enum.map(&table_cells/1)
      |> Enum.find(fn cells -> Enum.at(cells, 0) == "`#{short}`" end)

    case row do
      nil -> MapSet.new()
      cells -> cells |> Enum.at(2, "") |> backticked_module_names()
    end
  end

  defp table_cells(row) do
    row
    |> String.split("|")
    |> Enum.map(&String.trim/1)
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
    |> Enum.drop_while(&(&1 == ""))
    |> Enum.reverse()
  end

  # Backticked tokens that start with an uppercase letter — i.e. module short
  # names, excluding the lowercase `lib/...ex` path in the Declared-in cell.
  defp backticked_module_names(cell) do
    ~r/`([A-Z][A-Za-z0-9_]*)`/
    |> Regex.scan(cell, capture: :all_but_first)
    |> Enum.map(&List.first/1)
    |> MapSet.new()
  end

  defp actual_exports(view, boundary) do
    view
    |> Boundary.get(boundary)
    |> Map.fetch!(:exports)
    |> Enum.map(fn mod -> mod |> Module.split() |> List.last() end)
    |> MapSet.new()
  end
end
