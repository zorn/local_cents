defmodule LocalCents.Tracking.ExAutomerge do
  @moduledoc false

  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  @spec new_document() :: binary()
  def new_document, do: :erlang.nif_error(:nif_not_loaded)

  @spec add_expense(binary(), String.t(), number()) :: binary()
  def add_expense(_doc_bytes, _description, _amount),
    do: :erlang.nif_error(:nif_not_loaded)

  @spec list_expenses(binary()) :: [map()]
  def list_expenses(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  @spec merge(binary(), binary()) :: binary()
  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
