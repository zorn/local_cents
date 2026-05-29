defmodule LocalCents.Tracking.ExAutomerge do
  @moduledoc false

  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  def new_document, do: :erlang.nif_error(:nif_not_loaded)

  def add_expense(_doc_bytes, _description, _amount),
    do: :erlang.nif_error(:nif_not_loaded)

  def list_expenses(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)

  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
