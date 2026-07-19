# A project-local Credo check, loaded via the `requires:` key in `.credo.exs`
# so it stays out of the compiled application (Credo is a dev/test-only dep).
#
# Ported from zorn/flick (`Flick.Credo.Check.RawInHeex`).
defmodule LocalCents.CredoChecks.RawInHeex do
  use Credo.Check,
    base_priority: :high,
    category: :warning,
    explanations: [
      check: """
      Phoenix's `raw/1` marks its argument as already-safe, unescaped HTML.
      Inside a HEEx (`~H`) template this bypasses LiveView's automatic
      HTML-escaping, the primary defense against cross-site scripting (XSS).

      Neither Sobelow nor Credo's default checks look inside `~H` sigil
      contents, so `raw/1` calls in templates are invisible to the rest of our
      security tooling. This check closes that gap by scanning the template
      source of every `~H` sigil for `raw/1` calls.

      When you have deliberately produced safe HTML, opt out on a case-by-case
      basis with a `credo:allow-raw` marker in a HEEx comment on the same line
      as, or the line above, the `raw/1` call:

          <%!-- credo:allow-raw sanitized upstream --%>
          {raw(safe_html)}

      Opting out is a conscious decision to own the security implications of
      that specific `raw/1` call.
      """
    ]

  @allow_marker "credo:allow-raw"

  # A real `raw/1` call runs inside a HEEx interpolation, opened by either `{`
  # (attribute/body interpolation) or `<%= ` (EEx block). We require such an
  # opener before `raw(` so the literal text `raw(` in prose, HTML attributes,
  # or `<pre>` code samples is not flagged, and we scope each opener to its
  # own expression so the match cannot leak past the interpolation's close:
  #
  #   * `\{[^{}]*` — a brace interpolation; `[^{}]` stops at the closing `}`
  #     but still spans newlines, so `mix format` breaking a long `{ ... }`
  #     across lines is covered.
  #   * `<%=?(?:(?!%>).)*` — an EEx interpolation; the negative lookahead stops
  #     the body at the closing `%>` so a `<%= safe %>` followed by literal
  #     `raw(` in later prose is not a false positive.
  #
  # The `s` (dotall) flag lets the EEx body span lines too. `raw/1` written
  # without parens (`{raw @html}`) is intentionally not matched — it is rare,
  # and requiring `(` keeps the check free of variable/word false positives.
  @raw_call ~r/(?:\{[^{}]*|<%=?(?:(?!%>).)*)\braw\s*\(/s

  @impl Credo.Check
  def run(%SourceFile{} = source_file, params) do
    issue_meta = IssueMeta.for(source_file, params)
    Credo.Code.prewalk(source_file, &traverse(&1, &2, issue_meta))
  end

  # A HEEx template compiles to a `~H` sigil whose contents are a (dedented)
  # binary in the AST. `raw/1` calls live inside that binary, so we scan its
  # text rather than the surrounding Elixir AST.
  defp traverse({:sigil_H, meta, [{:<<>>, _, parts}, _modifiers]} = ast, issues, issue_meta) do
    template = parts |> Enum.filter(&is_binary/1) |> Enum.join()
    {ast, issues ++ raw_issues(template, meta[:line], issue_meta)}
  end

  defp traverse(ast, issues, _issue_meta) do
    {ast, issues}
  end

  defp raw_issues(template, sigil_line, issue_meta) do
    lines = String.split(template, "\n")

    @raw_call
    |> Regex.scan(template, return: :index)
    |> Enum.map(fn [{match_start, match_len} | _] ->
      # Report the line of the `raw(` itself (the end of the match), not the
      # interpolation opener, which may be several lines earlier.
      newlines_before(template, match_start + match_len - 1)
    end)
    |> Enum.uniq()
    |> Enum.reject(&allowed?(lines, &1))
    |> Enum.map(fn line_index -> issue_for(issue_meta, sigil_line + 1 + line_index) end)
  end

  # 0-based index of the line containing `byte_offset` = count of newline bytes
  # before it. Byte offsets from `Regex.scan/3` and newline counting agree
  # because `\n` is a single byte regardless of any UTF-8 around it.
  defp newlines_before(template, byte_offset) do
    <<prefix::binary-size(byte_offset), _::binary>> = template
    prefix |> :binary.matches("\n") |> length()
  end

  defp allowed?(lines, index) do
    current = Enum.at(lines, index, "")
    previous = if index > 0, do: Enum.at(lines, index - 1, ""), else: ""
    String.contains?(current, @allow_marker) or String.contains?(previous, @allow_marker)
  end

  defp issue_for(issue_meta, line_no) do
    format_issue(
      issue_meta,
      message:
        "Avoid `raw/1` in HEEx templates; it bypasses HTML escaping and risks XSS. " <>
          "Sanitize the content and add a `credo:allow-raw` marker to opt out.",
      trigger: "raw",
      line_no: line_no
    )
  end
end
