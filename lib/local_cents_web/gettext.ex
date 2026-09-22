defmodule LocalCentsWeb.Gettext do
  @moduledoc """
  A module providing Internationalization with a gettext-based API.

  By using [Gettext](https://hexdocs.pm/gettext), your module compiles translations
  that you can use in your application. To use this Gettext backend module,
  call `use Gettext` and pass it as an option:

      use Gettext, backend: LocalCentsWeb.Gettext

      # Simple translation
      gettext("Here is the string to translate")

      # Plural translation
      ngettext("Here is the string to translate",
               "Here are the strings to translate",
               3)

      # Domain-based translation
      dgettext("errors", "Here is the error message to translate")

  See the [Gettext Docs](https://hexdocs.pm/gettext) for detailed usage.
  """
  use Gettext.Backend, otp_app: :local_cents

  @doc """
  Translates a form or API error message into a display string.

  Form and API error messages are generated dynamically, so we translate them at
  render time by calling Gettext with this backend and the "errors" domain (whose
  translations live in the `errors.po` file). A `:count` option selects the plural
  form.
  """
  @spec translate_error({msg :: String.t(), opts :: keyword()}) :: String.t()
  def translate_error({msg, opts}) do
    if count = opts[:count] do
      Gettext.dngettext(__MODULE__, "errors", msg, msg, count, opts)
    else
      Gettext.dgettext(__MODULE__, "errors", msg, opts)
    end
  end
end
