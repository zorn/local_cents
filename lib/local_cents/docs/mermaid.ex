defmodule LocalCents.Docs.Mermaid do
  @moduledoc """
  The Mermaid diagrams embedded in our Markdown, and the machinery for proving
  they parse before they ship.

  A diagram that fails to parse is invisible to the build and lands on the
  published page as an error bomb; why that is and what it costs us is covered in
  [Mermaid Diagrams](mermaid-diagrams.html).

  This module is the pure half of the check that closes the gap: pull the blocks
  out of a file, build a page that runs them through `mermaid.parse()`, and read
  the verdict back out of the DOM that page leaves behind. `mix docs.mermaid` and
  `LocalCents.Docs.Mermaid.Runner` supply the parts that touch the world.

  `version/0` and `cdn_url/0` are the single source of the Mermaid pin: `mix.exs`
  interpolates `cdn_url/0` into the `<script>` tag ExDoc injects into every
  generated page, and the check fetches the same URL. Because Mermaid's grammar
  changes between versions, that shared source is what stops the check from
  blessing syntax our readers' browsers would reject.
  """

  defmodule Block do
    @moduledoc """
    One ```` ```mermaid ```` fence found in a Markdown file, located well enough
    to point a reader at it.

    `index` counts blocks within `file` (1-based) because that is how a human
    scanning the page thinks about them — "the second diagram" — while `line`
    gives an editor somewhere to jump to.
    """

    @type t() :: %__MODULE__{
            file: String.t(),
            index: pos_integer(),
            line: pos_integer(),
            source: String.t()
          }

    @enforce_keys [:file, :index, :line, :source]
    defstruct [:file, :index, :line, :source]
  end

  @typedoc """
  Each block's outcome, keyed by its position in the list handed to
  `harness_html/2`. `nil` means it parsed; a string is the parser's complaint.
  """
  @type results() :: %{non_neg_integer() => String.t() | nil}

  # Pinned deliberately rather than floated: a diagram that parses on latest may
  # not parse here, and the published docs load exactly this build.
  @version "10.2.3"

  # The id of the element the harness writes its base64 verdict into. Shared
  # between `harness_html/2` and `decode_results/1`, which are two ends of the
  # same wire.
  @results_id "mermaid-check-results"

  @doc "The pinned Mermaid version the docs load and the check validates against."
  @spec version() :: String.t()
  def version, do: @version

  @doc """
  The CDN URL for the pinned Mermaid build.

  Called from `mix.exs` to build the `<script>` tag ExDoc injects, and from
  `mix docs.mermaid` to fetch the same file for the check.
  """
  @spec cdn_url() :: String.t()
  def cdn_url, do: "https://cdn.jsdelivr.net/npm/mermaid@#{@version}/dist/mermaid.min.js"

  # An opening fence: at least three backticks followed by an info string. The
  # captured backticks matter because a closing fence must be at least as long as
  # the one that opened it, which is what lets a ````-fenced example contain a
  # ```mermaid fence without that inner fence being mistaken for a real diagram.
  @fence_open ~r/^\s*(?<fence>`{3,})\s*(?<info>[^`]*)$/
  @fence_close ~r/^\s*(?<fence>`{3,})\s*$/

  @doc """
  Pulls every Mermaid block out of `markdown`, tagging each with `file`.

  Fences of other languages are skipped, as is a Mermaid fence nested inside a
  wider fence — that is documentation *about* Mermaid, not a diagram anyone
  renders. A block left unterminated at end of file is still returned, so a
  truncated fence surfaces as a parse error rather than vanishing.
  """
  @spec extract_blocks(file :: String.t(), markdown :: String.t()) :: [Block.t()]
  def extract_blocks(file, markdown) do
    markdown
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.reduce(%{state: :outside, blocks: [], file: file}, &scan_line/2)
    |> close_trailing_block()
    |> Map.fetch!(:blocks)
    |> Enum.reverse()
  end

  defp scan_line({line_text, line_number}, %{state: :outside} = acc) do
    case Regex.named_captures(@fence_open, line_text) do
      %{"fence" => fence, "info" => info} ->
        if String.trim(info) == "mermaid" do
          %{acc | state: {:mermaid, fence, line_number, []}}
        else
          %{acc | state: {:other, fence}}
        end

      nil ->
        acc
    end
  end

  defp scan_line({line_text, _line_number}, %{state: {:other, fence}} = acc) do
    if closes?(line_text, fence), do: %{acc | state: :outside}, else: acc
  end

  defp scan_line({line_text, _line_number}, %{state: {:mermaid, fence, line, lines}} = acc) do
    if closes?(line_text, fence) do
      %{
        acc
        | state: :outside,
          blocks: [build_block(acc.file, acc.blocks, line, lines) | acc.blocks]
      }
    else
      %{acc | state: {:mermaid, fence, line, [line_text | lines]}}
    end
  end

  # A block still open at end of file is kept rather than dropped, so a truncated
  # fence reaches Mermaid and fails loudly. `lines` is newest-first, so dropping
  # from its head discards the empty line every file's trailing newline produces.
  defp close_trailing_block(%{state: {:mermaid, _fence, line, lines}} = acc) do
    lines = Enum.drop_while(lines, &(&1 == ""))

    %{
      acc
      | state: :outside,
        blocks: [build_block(acc.file, acc.blocks, line, lines) | acc.blocks]
    }
  end

  defp close_trailing_block(acc), do: acc

  defp build_block(file, prior_blocks, line, reversed_lines) do
    %Block{
      file: file,
      index: length(prior_blocks) + 1,
      line: line,
      source: reversed_lines |> Enum.reverse() |> Enum.join("\n")
    }
  end

  defp closes?(line_text, opening_fence) do
    case Regex.named_captures(@fence_close, line_text) do
      %{"fence" => fence} -> String.length(fence) >= String.length(opening_fence)
      nil -> false
    end
  end

  @doc """
  Builds the page that parses `blocks`, loading Mermaid from `mermaid_src`.

  Each block is tagged with its 0-based position in `blocks`, which is the key
  `decode_results/1` hands back. The page parses every block — one bad diagram
  must not hide the ones after it — then writes the whole verdict, base64-encoded,
  into a single element. Base64 keeps a parser error containing `<` or `&` from
  being re-escaped on its way through the dumped DOM.

  `mermaid_src` is loaded with a `src` attribute rather than inlined because a
  minified bundle may itself contain the characters that end a `<script>` element.
  The block payload is safe to inline because `:html_safe` encoding escapes `<`
  to `\\u003C`, so a diagram containing `</script>` cannot end the element early.
  """
  @spec harness_html(blocks :: [Block.t()], mermaid_src :: String.t()) :: String.t()
  def harness_html(blocks, mermaid_src) do
    payload =
      blocks
      |> Enum.with_index()
      |> Enum.map(fn {block, id} -> %{id: id, source: block.source} end)
      |> Jason.encode!(escape: :html_safe)

    """
    <!doctype html>
    <html>
      <head>
        <meta charset="utf-8">
        <title>Mermaid parse check</title>
      </head>
      <body>
        <div id="#{@results_id}"></div>
        <script src="#{mermaid_src}"></script>
        <script>
          const blocks = #{payload};

          mermaid.initialize({ startOnLoad: false, securityLevel: "strict" });

          (async () => {
            const results = [];

            for (const block of blocks) {
              try {
                await mermaid.parse(block.source);
                results.push({ id: block.id, error: null });
              } catch (error) {
                results.push({ id: block.id, error: String((error && error.message) || error) });
              }
            }

            const bytes = new TextEncoder().encode(JSON.stringify(results));
            let binary = "";
            for (const byte of bytes) binary += String.fromCharCode(byte);

            document.getElementById("#{@results_id}").textContent = btoa(binary);
          })();
        </script>
      </body>
    </html>
    """
  end

  @doc """
  Reads the verdict the harness left in `dumped_dom`.

  An absent or empty results element is an error rather than "everything passed":
  it means the page never finished — a browser crash, or a virtual-time budget
  that ran out mid-parse — and silently reporting that as success is exactly the
  failure mode this check exists to prevent.
  """
  @spec decode_results(dumped_dom :: String.t()) :: {:ok, results()} | {:error, String.t()}
  def decode_results(dumped_dom) do
    with {:ok, payload} <- extract_payload(dumped_dom),
         {:ok, json} <- decode_payload(payload) do
      {:ok, Map.new(json, &{&1["id"], &1["error"]})}
    end
  end

  defp extract_payload(dumped_dom) do
    case Regex.run(~r/id="#{@results_id}"[^>]*>([^<]*)</, dumped_dom, capture: :all_but_first) do
      [payload] when payload != "" ->
        {:ok, payload}

      _ ->
        {:error,
         "the browser did not report any parse results — the page may have crashed or timed out"}
    end
  end

  defp decode_payload(payload) do
    with {:ok, json} <- Base.decode64(payload),
         {:ok, results} when is_list(results) <- Jason.decode(json) do
      {:ok, results}
    else
      _ -> {:error, "the browser's parse results could not be read"}
    end
  end

  @doc """
  Pairs `blocks` back up with `results` and renders the failures, one line each:
  where the diagram is, then what Mermaid said about it.

  The pairing lives here, next to `harness_html/2`, because the two are the same
  contract seen from opposite ends — the position `harness_html/2` tags a block
  with is the key its verdict comes back under. Correlating in the caller would
  put half of that contract out of sight of the half that defines it.

  A block with no verdict at all is reported as a failure: the browser was asked
  about it and said nothing, so it went unchecked.
  """
  @spec failures(blocks :: [Block.t()], results()) :: [String.t()]
  def failures(blocks, results) do
    blocks
    |> Enum.with_index()
    |> Enum.flat_map(fn {block, id} ->
      case Map.fetch(results, id) do
        {:ok, nil} -> []
        {:ok, error} -> [format_failure(block, error)]
        :error -> [format_failure(block, "the browser reported no result")]
      end
    end)
  end

  defp format_failure(%Block{} = block, error) do
    "#{block.file}:#{block.line}|block #{block.index}|#{one_line(error)}"
  end

  defp one_line(error), do: error |> String.split("\n") |> Enum.map_join(" ", &String.trim/1)
end
