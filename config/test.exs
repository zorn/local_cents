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

# During a test run, if we get to the point where `BookStore.default_dir/0` is
# called and the process tree has no `:books_dir` set, then the offending test
# module either needs to pass a preferred `books_dir` into the function
# options or set the `ProcessConfig`. We never want to allow test logic to
# fall back to the default directory, which is the user space.
config :local_cents, LocalCents.Tracking.BookStore, raise_on_process_tree_dir_not_set: true

# Don't seed the demo library on an empty library during tests — seeding is
# side-effecting and slow. Only the tests that specifically cover it turn it back on.
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

# Suppress `:debug` and `:info` logs during test runs.
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
