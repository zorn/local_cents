defmodule LocalCents.Docs.MermaidTest do
  use ExUnit.Case, async: true

  alias LocalCents.Docs.Mermaid
  alias LocalCents.Docs.Mermaid.Block

  describe "extract_blocks/2" do
    test "returns no blocks for Markdown that has none" do
      markdown = """
      # A doc

      Some prose about `mermaid` that is not a diagram.
      """

      assert Mermaid.extract_blocks("docs/a.md", markdown) == []
    end

    test "captures the block's source, its per-file index, and its fence line" do
      markdown = """
      # A doc

      ```mermaid
      graph TD
          A --> B
      ```
      """

      assert [block] = Mermaid.extract_blocks("docs/a.md", markdown)
      assert %Block{file: "docs/a.md", index: 1, line: 3} = block
      assert block.source == "graph TD\n    A --> B"
    end

    test "numbers multiple blocks in the order they appear" do
      markdown = """
      ```mermaid
      graph TD
          A --> B
      ```

      Prose.

      ```mermaid
      sequenceDiagram
          A ->> B: hello
      ```
      """

      assert [first, second] = Mermaid.extract_blocks("docs/a.md", markdown)
      assert %Block{index: 1, line: 1} = first
      assert %Block{index: 2, line: 8} = second
      assert second.source == "sequenceDiagram\n    A ->> B: hello"
    end

    test "ignores fenced blocks of other languages" do
      markdown = """
      ```elixir
      # this mentions mermaid but is not one
      Mermaid.parse("graph TD")
      ```

      ```
      graph TD
      ```
      """

      assert Mermaid.extract_blocks("docs/a.md", markdown) == []
    end

    test "ignores a mermaid fence nested inside a wider fence" do
      markdown = """
      Here is how you write one:

      ````markdown
      ```mermaid
      graph TD
      ```
      ````
      """

      assert Mermaid.extract_blocks("docs/a.md", markdown) == []
    end

    test "preserves blank lines and indentation inside a block" do
      markdown = """
      ```mermaid
      graph TD
          A --> B

          classDef x fill:#fff;
      ```
      """

      assert [block] = Mermaid.extract_blocks("docs/a.md", markdown)
      assert block.source == "graph TD\n    A --> B\n\n    classDef x fill:#fff;"
    end

    test "tolerates trailing whitespace on the opening fence" do
      markdown = "```mermaid  \ngraph TD\n```\n"

      assert [%Block{source: "graph TD"}] = Mermaid.extract_blocks("docs/a.md", markdown)
    end

    test "captures a block left unterminated at end of file" do
      markdown = "```mermaid\ngraph TD\n"

      assert [%Block{source: "graph TD"}] = Mermaid.extract_blocks("docs/a.md", markdown)
    end
  end

  describe "harness_html/2" do
    setup do
      blocks = [
        %Block{file: "docs/a.md", index: 1, line: 3, source: "graph TD\n    A --> B"},
        %Block{file: "docs/b.md", index: 1, line: 9, source: "sequenceDiagram\n    A ->> B: hi"}
      ]

      %{blocks: blocks, html: Mermaid.harness_html(blocks, "mermaid.min.js")}
    end

    test "loads the given Mermaid script", %{html: html} do
      assert html =~ ~s(src="mermaid.min.js")
    end

    test "carries every block's source into the page payload", %{blocks: blocks, html: html} do
      assert payload(html) == [
               %{"id" => 0, "source" => Enum.at(blocks, 0).source},
               %{"id" => 1, "source" => Enum.at(blocks, 1).source}
             ]
    end

    test "includes the element the results are written to", %{html: html} do
      assert html =~ ~s(id="mermaid-check-results")
    end

    test "escapes a closing script tag that appears inside a block's source" do
      source = "graph TD\n  A[\"</script><script>alert(1)</script>\"]"
      blocks = [%Block{file: "docs/a.md", index: 1, line: 1, source: source}]
      html = Mermaid.harness_html(blocks, "mermaid.min.js")
      script = html |> String.split("const blocks = ") |> List.last()

      # The source survives intact for the parser, but never as literal markup
      # that would end the harness's own script element.
      assert payload(html) == [%{"id" => 0, "source" => source}]
      refute script =~ "</script><script>"
    end

    # Pulls the JSON the harness hands to the browser back out of the page.
    defp payload(html) do
      [json] = Regex.run(~r/const blocks = (.+);$/m, html, capture: :all_but_first)
      Jason.decode!(json)
    end
  end

  describe "decode_results/1" do
    defp dump(results) do
      payload = results |> Jason.encode!() |> Base.encode64()
      ~s(<html><body><div id="mermaid-check-results">#{payload}</div></body></html>)
    end

    test "maps a passing block to nil and a failing block to its error" do
      dom = dump([%{id: 0, error: nil}, %{id: 1, error: "Parse error on line 2"}])

      assert Mermaid.decode_results(dom) == {:ok, %{0 => nil, 1 => "Parse error on line 2"}}
    end

    test "errors when the results element is missing" do
      assert {:error, message} = Mermaid.decode_results("<html><body>nothing here</body></html>")
      assert message =~ "did not report"
    end

    test "errors when the results element is empty, as when the page timed out" do
      emptied = String.replace(dump([]), ~r/>[^<]*</, "><")

      assert {:error, message} = Mermaid.decode_results(emptied)
      assert message =~ "did not report"
    end

    test "errors when the payload is not decodable" do
      dom = ~s(<div id="mermaid-check-results">not-base64!!</div>)

      assert {:error, message} = Mermaid.decode_results(dom)
      assert message =~ "could not be read"
    end
  end

  describe "failures/2" do
    setup do
      blocks = [
        %Block{file: "docs/a.md", index: 1, line: 3, source: "graph TD"},
        %Block{file: "docs/a.md", index: 2, line: 42, source: "graph TD"},
        %Block{file: "docs/b.md", index: 1, line: 9, source: "graph TD"}
      ]

      %{blocks: blocks}
    end

    test "reports nothing when every block parsed", %{blocks: blocks} do
      assert Mermaid.failures(blocks, %{0 => nil, 1 => nil, 2 => nil}) == []
    end

    test "renders the pipe-delimited location and error for each failure", %{blocks: blocks} do
      results = %{0 => nil, 1 => "Parse error on line 2", 2 => "Expecting 'SPACE'"}

      assert Mermaid.failures(blocks, results) == [
               "docs/a.md:42|block 2|Parse error on line 2",
               "docs/b.md:9|block 1|Expecting 'SPACE'"
             ]
    end

    test "flattens a multi-line parser error onto one line", %{blocks: blocks} do
      results = %{
        0 => "Parse error on line 2:\n  ...A --> B\n  ---^\ngot 'DESCR'",
        1 => nil,
        2 => nil
      }

      assert [failure] = Mermaid.failures(blocks, results)
      assert failure == "docs/a.md:3|block 1|Parse error on line 2: ...A --> B ---^ got 'DESCR'"
    end

    test "treats a block the browser never reported on as a failure", %{blocks: blocks} do
      assert Mermaid.failures(blocks, %{0 => nil, 1 => nil}) == [
               "docs/b.md:9|block 1|the browser reported no result"
             ]
    end
  end
end
