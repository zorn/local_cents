defmodule Storybook.Composites.ReportMatrix do
  use LocalCentsWeb.Storybook.Story, :component

  alias LocalCentsWeb.ReportPresenter.Cell
  alias LocalCentsWeb.ReportPresenter.Column
  alias LocalCentsWeb.ReportPresenter.Row
  alias LocalCentsWeb.ReportPresenter.ViewModel

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
    %ViewModel{
      empty?: false,
      months: [%Column{label: "May '26"}, %Column{label: "Jun '26"}, %Column{label: "Jul '26"}],
      rows: [
        %Row{
          name: "Groceries",
          cells: [
            %Cell{kind: :money, text: "$184.50"},
            %Cell{kind: :zero},
            %Cell{kind: :money, text: "$96.20"}
          ],
          total: %Cell{kind: :money, text: "$280.70"}
        },
        %Row{
          name: "Uncategorized",
          cells: [
            %Cell{kind: :zero},
            %Cell{kind: :needs, count: 2},
            %Cell{kind: :money_needs, text: "$38.50", count: 1}
          ],
          total: %Cell{kind: :money_needs, text: "$38.50", count: 3}
        }
      ],
      column_totals: [
        %Cell{kind: :money, text: "$184.50"},
        %Cell{kind: :needs, count: 2},
        %Cell{kind: :money_needs, text: "$134.70", count: 1}
      ],
      grand_total: %Cell{kind: :money_needs, text: "$319.20", count: 3}
    }
  end

  # A span too wide to fit, so the Category and Total columns freeze while the Month
  # cells scroll. Totals are internally consistent: two full-money rows plus an
  # Uncategorized row that is all zeros but for a trailing needs-amount count.
  @abbrev {"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"}

  defp wide_span do
    n = 14
    last = n - 1

    %ViewModel{
      empty?: false,
      months: for(o <- 0..last, do: %Column{label: wide_label(o)}),
      rows: [
        %Row{
          name: "Groceries",
          cells: for(_ <- 0..last, do: %Cell{kind: :money, text: "$120.00"}),
          total: %Cell{kind: :money, text: "$1680.00"}
        },
        %Row{
          name: "Utilities",
          cells: for(_ <- 0..last, do: %Cell{kind: :money, text: "$80.00"}),
          total: %Cell{kind: :money, text: "$1120.00"}
        },
        %Row{
          name: "Uncategorized",
          cells:
            for(
              o <- 0..last,
              do: if(o == last, do: %Cell{kind: :needs, count: 2}, else: %Cell{kind: :zero})
            ),
          total: %Cell{kind: :needs, count: 2}
        }
      ],
      column_totals:
        for o <- 0..last do
          if o == last,
            do: %Cell{kind: :money_needs, text: "$200.00", count: 2},
            else: %Cell{kind: :money, text: "$200.00"}
        end,
      grand_total: %Cell{kind: :money_needs, text: "$2800.00", count: 2}
    }
  end

  # Month labels marching Jan '25 → Feb '26 by column offset.
  defp wide_label(offset) do
    "#{elem(@abbrev, rem(offset, 12))} '#{25 + div(offset, 12)}"
  end

  defp single_month do
    %ViewModel{
      empty?: false,
      months: [%Column{label: "Jul '26"}],
      rows: [
        %Row{
          name: "Housing",
          cells: [%Cell{kind: :money, text: "$2150.00"}],
          total: %Cell{kind: :money, text: "$2150.00"}
        }
      ],
      column_totals: [%Cell{kind: :money, text: "$2150.00"}],
      grand_total: %Cell{kind: :money, text: "$2150.00"}
    }
  end
end
