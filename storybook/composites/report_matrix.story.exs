defmodule Storybook.Composites.ReportMatrix do
  use LocalCentsWeb.Storybook.Story, :component

  def function, do: &Bond.Composites.ReportMatrix.report_matrix/1
  def render_source, do: :function

  def variations do
    [
      %Variation{
        id: :populated,
        description: "A three-month matrix exercising every cell kind, with totals.",
        attributes: %{id: "report-matrix-populated", report: populated()}
      },
      %Variation{
        id: :single_month,
        description: "A one-column report — the narrowest a populated matrix gets.",
        attributes: %{id: "report-matrix-single", report: single_month()}
      },
      %Variation{
        id: :wide_span,
        description: "A 14-month span — exercises the frozen columns and horizontal scroll.",
        attributes: %{id: "report-matrix-wide", report: wide_span()}
      }
    ]
  end

  # All four cell kinds appear: known money, a genuine zero, a bare needs-amount count,
  # and money-plus-needs — including in the row, column, and grand totals.
  defp populated do
    %{
      empty?: false,
      months: [%{label: "May '26"}, %{label: "Jun '26"}, %{label: "Jul '26"}],
      rows: [
        %{
          name: "Groceries",
          cells: [
            %{kind: :money, text: "$184.50"},
            %{kind: :zero},
            %{kind: :money, text: "$96.20"}
          ],
          total: %{kind: :money, text: "$280.70"}
        },
        %{
          name: "Uncategorized",
          cells: [
            %{kind: :zero},
            %{kind: :needs, count: 2},
            %{kind: :money_needs, text: "$38.50", count: 1}
          ],
          total: %{kind: :money_needs, text: "$38.50", count: 3}
        }
      ],
      column_totals: [
        %{kind: :money, text: "$184.50"},
        %{kind: :needs, count: 2},
        %{kind: :money_needs, text: "$134.70", count: 1}
      ],
      grand_total: %{kind: :money_needs, text: "$319.20", count: 3}
    }
  end

  # A span too wide to fit, so the Category and Total columns freeze while the Month
  # cells scroll. Totals are internally consistent: two full-money rows plus an
  # Uncategorized row that is all zeros but for a trailing needs-amount count.
  @abbrev {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

  defp wide_span do
    n = 14
    last = n - 1

    %{
      empty?: false,
      months: for(o <- 0..last, do: %{label: wide_label(o)}),
      rows: [
        %{
          name: "Groceries",
          cells: for(_ <- 0..last, do: %{kind: :money, text: "$120.00"}),
          total: %{kind: :money, text: "$1680.00"}
        },
        %{
          name: "Utilities",
          cells: for(_ <- 0..last, do: %{kind: :money, text: "$80.00"}),
          total: %{kind: :money, text: "$1120.00"}
        },
        %{
          name: "Uncategorized",
          cells:
            for(
              o <- 0..last,
              do: if(o == last, do: %{kind: :needs, count: 2}, else: %{kind: :zero})
            ),
          total: %{kind: :needs, count: 2}
        }
      ],
      column_totals:
        for o <- 0..last do
          if o == last,
            do: %{kind: :money_needs, text: "$200.00", count: 2},
            else: %{kind: :money, text: "$200.00"}
        end,
      grand_total: %{kind: :money_needs, text: "$2800.00", count: 2}
    }
  end

  # Month labels marching Jan '25 → Feb '26 by column offset.
  defp wide_label(offset) do
    "#{elem(@abbrev, rem(offset, 12))} '#{25 + div(offset, 12)}"
  end

  defp single_month do
    %{
      empty?: false,
      months: [%{label: "Jul '26"}],
      rows: [
        %{
          name: "Housing",
          cells: [%{kind: :money, text: "$2150.00"}],
          total: %{kind: :money, text: "$2150.00"}
        }
      ],
      column_totals: [%{kind: :money, text: "$2150.00"}],
      grand_total: %{kind: :money, text: "$2150.00"}
    }
  end
end
