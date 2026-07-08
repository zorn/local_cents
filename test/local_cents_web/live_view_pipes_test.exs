defmodule LocalCentsWeb.LiveViewPipesTest do
  use ExUnit.Case, async: true

  import LocalCentsWeb.LiveViewPipes

  alias Phoenix.LiveView.Socket

  describe "ok/1" do
    test "wraps a socket in an :ok mount tuple" do
      socket = %Socket{}

      assert {:ok, ^socket} = ok(socket)
    end

    test "reads as the tail of a pipeline" do
      assert {:ok, %Socket{assigns: %{count: 1}}} =
               %Socket{} |> Phoenix.Component.assign(count: 1) |> ok()
    end
  end

  describe "noreply/1" do
    test "wraps a socket in a :noreply callback tuple" do
      socket = %Socket{}

      assert {:noreply, ^socket} = noreply(socket)
    end

    test "reads as the tail of a pipeline" do
      assert {:noreply, %Socket{assigns: %{count: 1}}} =
               %Socket{} |> Phoenix.Component.assign(count: 1) |> noreply()
    end
  end
end
