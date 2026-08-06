ExUnit.start()

# The fallback books directory is unique per run (config/test.exs), so it begins
# empty by construction and anything in it at the end was written by a test that
# reached the books directory without claiming one — or by work that outlived the
# test that started it and so lost the claim. Report that rather than deleting the
# evidence; remove the directory only when it is clean, so runs do not leave a trail
# of empty directories behind. See `LocalCents.ProcessConfig` for the seam that lets
# a test claim its own directory.
books_dir = Application.fetch_env!(:local_cents, :books_dir)

ExUnit.after_suite(fn _results ->
  case File.ls(books_dir) do
    {:ok, []} ->
      File.rm_rf(books_dir)

    {:ok, files} ->
      # `IO.warn/2` with an empty stacktrace: stderr, no misleading call site.
      IO.warn(
        """
        #{length(files)} file(s) reached the fallback books directory.
          #{books_dir}
        Some test read or wrote the books directory without claiming one, or started \
        work that outlived it — a process still running after the test returns can no \
        longer resolve the claim.\
        """,
        []
      )

    {:error, :enoent} ->
      :ok

    {:error, reason} ->
      IO.warn("could not check #{books_dir}: #{inspect(reason)}", [])
  end
end)
