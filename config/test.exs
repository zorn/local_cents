import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :local_cents, LocalCentsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dlPkhdeYGwn/67z7s5GX65OFhB5tZ0nUIK9Lmp9DYZnQi1fOBqwGqKP6CtTDLbVn",
  server: false

# In test we don't send emails
config :local_cents, LocalCents.Mailer, adapter: Swoosh.Adapters.Test

# Resolve the settings below through the calling process's tree before the
# application env, so a test can claim its own value instead of mutating a global
# that every concurrent test shares. This is what lets the whole suite run
# `async: true`; see `LocalCents.ProcessConfig` and docs/async-testing.md.
config :local_cents, LocalCents.ProcessConfig, scoped_to_process_tree: true

# Persist Books to a temporary directory during tests so runs never touch the
# real application-support location. This is the fallback for tests that never
# write a Book; the LiveView feature tests claim their own directory per-test via
# `LocalCents.BooksDirHelper`, while unit and context tests bypass it entirely by
# injecting their own `@tag :tmp_dir` directory.
config :local_cents, :books_dir, Path.join(System.tmp_dir!(), "local_cents_test_books")

# Don't seed the demo library on an empty library during tests — seeding is
# side-effecting and slow (it writes the whole document per expense), and only the
# tests that specifically cover it claim it back on for their own process tree. It
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

# Let every level through the primary logger, but print only warnings and errors.
# The split matters: `ExUnit.CaptureLog` cannot see a message the *primary* level
# already filtered, so a test asserting on a debug log would otherwise have to lift
# the level at runtime — a node-wide mutation that forces `async: false` on its whole
# module, and whose behavior ExUnit documents as undetermined under async. Keeping
# the default handler at :warning holds the suite's output to what it was.
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
