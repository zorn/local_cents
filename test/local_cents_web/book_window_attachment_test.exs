defmodule LocalCentsWeb.BookWindowAttachmentTest do
  # Guards the `LocalCentsWeb.BookWindow` mount contract against a view that is
  # routed as a document window but never attaches the hook. Nothing in Phoenix
  # enforces this: a view missing the hook compiles, mounts, and renders, and
  # only fails later and invisibly — it never registers a viewer, so its Book's
  # runtime can reap under an open window (see
  # `docs/research/book-window-on-mount-contract.md`).
  use ExUnit.Case, async: true

  @hook_module LocalCentsWeb.BookWindow
  @hook_id {@hook_module, :default}
  @path_prefix "/books/:book_id"

  test "every routed document-window view attaches the BookWindow on_mount hook" do
    views = document_window_views()

    assert views != [],
           "No #{@path_prefix} LiveView routes found. Did the document-window path change? " <>
             "This test enumerates routes by path prefix, so a rename makes it vacuously pass."

    for view <- views do
      hook_ids = Enum.map(view.__live__().lifecycle.mount, & &1.id)

      assert @hook_id in hook_ids, """
      #{inspect(view)} is routed under #{@path_prefix} but does not attach the
      #{inspect(@hook_module)} on_mount hook, so it will never register a viewer and
      its Book's runtime can reap under an open window.

      Add this under the `use LocalCentsWeb, :live_view` line:

          on_mount #{inspect(@hook_module)}

      attached hooks: #{inspect(hook_ids)}
      """
    end
  end

  # Reads the module's own baked-in hook list rather than the route's
  # `live_session.extra.on_mount`, because this repo attaches per module. Both
  # are `@doc false` internals, but `__live__/0`'s contents are documented in
  # `Phoenix.LiveView.__live__/1` and it is what the framework itself loads the
  # lifecycle from on both render paths, so it is the more stable of the two.
  defp document_window_views do
    # The `<-` over a one-element list is a filter, not a match: a non-LiveView route
    # under this prefix (an export endpoint, say) has no `:phoenix_live_view` metadata
    # and is skipped rather than raising.
    for route <- LocalCentsWeb.Router.__routes__(),
        String.starts_with?(route.path, @path_prefix),
        {view, _action, _opts, _live_session} <- [route.metadata[:phoenix_live_view]],
        do: view
  end
end
