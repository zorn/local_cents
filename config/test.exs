import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :local_cents, LocalCentsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dlPkhdeYGwn/67z7s5GX65OFhB5tZ0nUIK9Lmp9DYZnQi1fOBqwGqKP6CtTDLbVn",
  server: false

# In test we don't send emails
config :local_cents, LocalCents.Mailer, adapter: Swoosh.Adapters.Test

# Allows for `async: true` on LiveView tests.
config :local_cents, LocalCents.ProcessConfig, scoped_to_process_tree: true

# Persist Books to a temporary directory during tests so runs never touch the
# real application-support location. Still load-bearing even though every test now
# claims or injects its own directory: without it `BookStore.default_dir/0` falls
# through to `~/Library/Application Support/LocalCents/books`, so any test that
# reaches the books directory without claiming one — a dead render of /library, say
# — would enumerate and create the developer's actual library. This is the backstop
# for that, not a directory tests are expected to use.
#
# Keyed by OS pid so two runs never share it. The path is otherwise identical for
# every checkout on the machine, and this repo's workflow routinely has more than
# one worktree running `mix test` at once — mix's build lock keeps one checkout
# from racing itself, and does nothing across checkouts.
config :local_cents,
       :books_dir,
       Path.join(System.tmp_dir!(), "local_cents_test_books_#{System.pid()}")

# Don't seed the demo library on an empty library during tests — seeding is
# side-effecting and slow (it writes the whole document per expense), and only the
# tests that specifically cover it turn it back on for their own process tree. It
# defaults on (dev, prod), so a developer's empty library still gets the demos.
config :local_cents, :demo_seeding, false

# Shrink the BookServer viewer-disconnect grace period (default 60s — see
# `config/config.exs`) so the auto-shutdown suite observes a reap promptly. Kept below
# 100ms so a `refute_receive` window (house rule: literal <= 100) still outlasts a
# wrongful reap; a viewer re-registering within the window (the navigation-gap test)
# cancels the pending reap in the low-single-digit ms it takes to propagate locally.
config :local_cents, LocalCents.Tracking.BookServer, viewer_grace_ms: 50

# The endpoint PhoenixTest drives when running feature tests.
config :phoenix_test, :endpoint, LocalCentsWeb.Endpoint

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Two `config :logger` lines because these are two different knobs, not a repeat.
# The first is the *primary* level, the gate every message passes before any handler
# sees it. The second is the level of the *default handler*, the one that prints to
# the console. Letting everything past the gate while the console still prints only
# warnings and errors is what lets a test assert on a debug message via
# `ExUnit.CaptureLog` — which adds a handler of its own, and so can only ever see
# what the primary level already let through — without lifting the level at runtime.
# Lifting it at runtime is the thing to avoid: it is a node-wide mutation, so the
# module doing it would have to drop `async: true`.
config :logger, level: :debug
config :logger, :default_handler, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
