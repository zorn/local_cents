defmodule LocalCentsWeb.Storybook do
  use PhoenixStorybook,
    otp_app: :local_cents,
    content_path: Path.expand("../../storybook", __DIR__),
    # assets path are remote path, not local file-system paths
    css_path: "/assets/storybook.css",
    js_path: "/assets/storybook.js",
    # Ex: "https://github.com/my-org/my-app/blob/main"
    # source_permalink_base_url: "https://github.com/my-org/my-app/blob/main",
    sandbox_class: "local-cents"
end
