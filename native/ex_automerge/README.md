# NIF for LocalCents.Tracking.ExAutomerge

## To build the NIF module:

- Your NIF will now build along with your project.

## To load the NIF:

```elixir
defmodule LocalCents.Tracking.ExAutomerge do
  use Rustler, otp_app: :local_cents, crate: "ex_automerge"

  # When your NIF is loaded, it will override these functions.
  def new_document(_name, _time), do: :erlang.nif_error(:nif_not_loaded)
  def document_name(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)
  def document_updated_at(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)
  def decode(_doc_bytes), do: :erlang.nif_error(:nif_not_loaded)
  def reconcile(_prior_bytes, _new_state, _time), do: :erlang.nif_error(:nif_not_loaded)
  def merge(_left_bytes, _right_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
```

## Examples

[This](https://github.com/rusterlium/NifIo) is a complete example of a NIF written in Rust.
