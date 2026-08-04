# Start each run from an empty fallback books directory. Feature tests claim their
# own directory per test (see docs/async-testing.md), so nothing should ever be
# written here — but a test that abandons in-flight work loses its claim and the
# writes land here instead. Clearing it up front keeps that a visible leak from
# this run rather than sediment that quietly grows a library other tests read.
:local_cents |> Application.get_env(:books_dir) |> File.rm_rf!()

ExUnit.start()
