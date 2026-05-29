defmodule LocalCents.Tracking.Expense do
  @moduledoc """
  A financial transaction that represents money the user has spent.

  ## Future Enhancements

  - For now we will store amount as an integer number of cents just to get
    something working. In the near future this will need to be refactored to a
    proper decimal type with likely various currency support.
  - Q: Do we want to allow negative expenses?
  """

  @enforce_keys [:description, :amount]
  defstruct description: nil, amount: nil

  @type t() :: %__MODULE__{
          description: String.t(),
          amount: integer()
        }
end
