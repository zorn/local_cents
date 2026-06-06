defmodule LocalCentsWeb.Storybook do
  @moduledoc """
  Provides a UI component catalog and playground for developers to design,
  document and test UI components in isolation.
  """

  use PhoenixStorybook,
    otp_app: :local_cents,
    content_path: Path.expand("../../storybook", __DIR__),
    # asset paths are remote URL paths, not local file-system paths
    css_path: "/assets/storybook.css",
    js_path: "/assets/js/storybook.js",
    # Ex: "https://github.com/my-org/my-app/blob/main"
    # source_permalink_base_url: "https://github.com/my-org/my-app/blob/main",
    sandbox_class: "local-cents"
end
