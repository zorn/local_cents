import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :local_cents, LocalCentsWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dlPkhdeYGwn/67z7s5GX65OFhB5tZ0nUIK9Lmp9DYZnQi1fOBqwGqKP6CtTDLbVn",
  server: false

# In test we don't send emails
config :local_cents, LocalCents.Mailer, adapter: Swoosh.Adapters.Test

# Persist Books to a temporary directory during tests so runs never touch the
# real application-support location. This is the default `BookStore.default_dir/0`
# resolves to; the LiveView feature tests override it per-test via
# `LocalCents.BooksDirHelper` (they run `async: false`), while unit and context
# tests bypass it entirely by injecting their own `@tag :tmp_dir` directory.
config :local_cents, :books_dir, Path.join(System.tmp_dir!(), "local_cents_test_books")

# Don't seed the demo library on an empty library during tests — seeding is
# side-effecting and slow (it writes the whole document per expense), and only the
# tests that specifically cover it opt back in via `Application.put_env/3`. It
# defaults on (dev, prod), so a developer's empty library still gets the demos.
config :local_cents, :demo_seeding, false

# The endpoint PhoenixTest drives when running feature tests.
config :phoenix_test, :endpoint, LocalCentsWeb.Endpoint

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
