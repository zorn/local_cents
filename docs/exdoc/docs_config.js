// ExDoc's page template unconditionally emits `<script defer src="docs_config.js">`
// as the hook for its version-dropdown feature, but only writes the file itself
// when the project configures version nodes. LocalCents has no version dropdown,
// so ExDoc never generated `doc/docs_config.js`. Every dev doc page then requested
// a missing `/doc/docs_config.js`, which fell through the dev-only `/doc` static
// plug to the router and raised `NoRouteError` into the log — one info line plus a
// full debug stacktrace per page view (issue #253).
//
// mix.exs copies this empty stub into the docs output on every `mix docs`, so the
// request resolves 200 and the dropdown code runs against an empty list (renders
// nothing). Cosmetic fix; the `/doc` plug is dev-only and never runs in a release.
var versionNodes = [];
