defmodule LocalCents.GuardrailTest do
  use ExUnit.Case, async: true

  alias LocalCents.Guardrail
  alias LocalCents.Guardrail.Violation

  describe "review/2 — net-new skips" do
    test "flags an added credo:disable-for-next-line in an Elixir source file" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      index 1111111..2222222 100644
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,0 +11,2 @@ defmodule Foo do
      +  # credo:disable-for-next-line Credo.Check.Readability.Specs
      +  def bar, do: :ok
      """

      assert [%Violation{kind: :credo_skip, file: "lib/foo.ex", line: 11}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "flags an added credo:disable-for-this-file" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -0,0 +1 @@
      +# credo:disable-for-this-file Credo.Check.Refactor.ModuleDependencies
      """

      assert [%Violation{kind: :credo_skip, file: "lib/foo.ex", line: 1}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "flags an added sobelow_skip" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -20,0 +21 @@
      +  # sobelow_skip ["Traversal.FileModule"]
      """

      assert [%Violation{kind: :sobelow_skip, file: "lib/foo.ex", line: 21}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "advances the line number past context lines within a hunk" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10,2 +10,3 @@
       def existing do
      +  # credo:disable-for-next-line Credo.Check.Readability.Specs
         :ok
      """

      assert [%Violation{kind: :credo_skip, line: 11}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "attributes lines correctly across multiple hunks" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -5,0 +6 @@
      +  # credo:disable-for-next-line Credo.Check.Readability.Specs
      @@ -40,0 +42,2 @@
      +  something = :ok
      +  # sobelow_skip ["Traversal.FileModule"]
      """

      assert [
               %Violation{kind: :credo_skip, line: 6},
               %Violation{kind: :sobelow_skip, line: 43}
             ] = Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "flags the disable-for-previous-line and disable-for-lines Credo forms" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -5,0 +6 @@
      +  # credo:disable-for-previous-line Credo.Check.Readability.Specs
      @@ -20,0 +21 @@
      +  # credo:disable-for-lines:2 Credo.Check.Readability.Specs
      """

      assert [
               %Violation{kind: :credo_skip, line: 6},
               %Violation{kind: :credo_skip, line: 21}
             ] = Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "does not misread an added `++ ...` line as a file header" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -5,0 +6,2 @@
      +++ list_tail
      +  # credo:disable-for-next-line Credo.Check.Readability.Specs
      """

      assert [%Violation{kind: :credo_skip, file: "lib/foo.ex", line: 7}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "does not flag a removed skip line" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +9,0 @@
      -  # credo:disable-for-next-line Credo.Check.Readability.Specs
      """

      assert Guardrail.review(diff, ["lib/foo.ex"]) == []
    end

    test "flags an edited skip line on its new side" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -10 +10 @@
      -  # credo:disable-for-this-file Credo.Check.Readability.Specs
      +  # credo:disable-for-this-file Credo.Check.Readability.Specs, Credo.Check.Design.AliasUsage
      """

      assert [%Violation{kind: :credo_skip, file: "lib/foo.ex", line: 10}] =
               Guardrail.review(diff, ["lib/foo.ex"])
    end

    test "does not flag edits to a file that leave its existing skips untouched" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -30,0 +31 @@
      +  def unrelated, do: :ok
      """

      assert Guardrail.review(diff, ["lib/foo.ex"]) == []
    end

    test "does not flag a skip pattern in a non-Elixir file" do
      diff = """
      diff --git a/CODING_STANDARDS.md b/CODING_STANDARDS.md
      --- a/CODING_STANDARDS.md
      +++ b/CODING_STANDARDS.md
      @@ -0,0 +1 @@
      +# credo:disable-for-this-file is an example directive
      """

      assert Guardrail.review(diff, ["CODING_STANDARDS.md"]) == []
    end

    test "does not flag a skip pattern that appears inside a string literal" do
      diff = """
      diff --git a/test/local_cents/guardrail_test.exs b/test/local_cents/guardrail_test.exs
      --- a/test/local_cents/guardrail_test.exs
      +++ b/test/local_cents/guardrail_test.exs
      @@ -0,0 +1 @@
      +      "+  # credo:disable-for-next-line Credo.Check.Readability.Specs",
      """

      assert Guardrail.review(diff, ["test/local_cents/guardrail_test.exs"]) == []
    end
  end

  describe "review/2 — guardrail config and workflow edits" do
    test "flags a change to .credo.exs" do
      assert [%Violation{kind: :config, file: ".credo.exs", line: nil}] =
               Guardrail.review("", [".credo.exs"])
    end

    test "flags a change to .sobelow-conf" do
      assert [%Violation{kind: :config, file: ".sobelow-conf"}] =
               Guardrail.review("", [".sobelow-conf"])
    end

    test "flags a .credo.exs in a config subdirectory" do
      assert [%Violation{kind: :config, file: "config/.credo.exs"}] =
               Guardrail.review("", ["config/.credo.exs"])
    end

    test "flags a change to a workflow file" do
      assert [%Violation{kind: :workflow, file: ".github/workflows/code-quality.yaml"}] =
               Guardrail.review("", [".github/workflows/code-quality.yaml"])
    end

    test "flags a workflow file with the .yml extension" do
      assert [%Violation{kind: :workflow, file: ".github/workflows/ci.yml"}] =
               Guardrail.review("", [".github/workflows/ci.yml"])
    end

    test "does not flag an unrelated file" do
      assert Guardrail.review("", ["lib/local_cents/tracking.ex", "README.md"]) == []
    end
  end

  describe "review/2 — combined and clean" do
    test "returns an empty list for a diff that weakens nothing" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -1,0 +2 @@
      +  def added, do: :ok
      """

      assert Guardrail.review(diff, ["lib/foo.ex"]) == []
    end

    test "reports skips ahead of config and workflow edits" do
      diff = """
      diff --git a/lib/foo.ex b/lib/foo.ex
      --- a/lib/foo.ex
      +++ b/lib/foo.ex
      @@ -0,0 +1 @@
      +# credo:disable-for-this-file Credo.Check.Readability.Specs
      """

      assert [
               %Violation{kind: :credo_skip},
               %Violation{kind: :config},
               %Violation{kind: :workflow}
             ] =
               Guardrail.review(diff, [
                 "lib/foo.ex",
                 ".credo.exs",
                 ".github/workflows/code-quality.yaml"
               ])
    end
  end

  describe "format/1" do
    test "returns nil when there are no violations" do
      assert Guardrail.format([]) == nil
    end

    test "names each offending file and line across every kind" do
      violations = [
        %Violation{
          kind: :credo_skip,
          file: "lib/foo.ex",
          line: 11,
          detail: "# credo:disable-for-next-line Credo.Check.Readability.Specs"
        },
        %Violation{
          kind: :sobelow_skip,
          file: "lib/bar.ex",
          line: 4,
          detail: ~s(# sobelow_skip ["Traversal.FileModule"])
        },
        %Violation{kind: :config, file: ".credo.exs"},
        %Violation{kind: :workflow, file: ".github/workflows/code-quality.yaml"}
      ]

      message = Guardrail.format(violations)

      assert message =~ "lib/foo.ex:11 adds a Credo skip"
      assert message =~ "lib/bar.ex:4 adds a Sobelow skip"
      assert message =~ ".credo.exs is a guardrail config file"
      assert message =~ ".github/workflows/code-quality.yaml is a CI workflow file"
    end
  end
end
