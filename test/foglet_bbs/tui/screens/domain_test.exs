defmodule Foglet.TUI.Screens.DomainTest do
  use ExUnit.Case, async: true

  alias Foglet.TUI.Screens.Domain

  describe "get/2" do
    test "returns {:ok, module} when key is configured" do
      ctx = %{domain: %{boards: SomeBoardsMod}}
      assert Domain.get(ctx, :boards) == {:ok, SomeBoardsMod}
    end

    test "returns {:ok, module} for all four supported keys" do
      ctx = %{domain: %{boards: ModB, threads: ModT, posts: ModP, markdown: ModM}}
      assert Domain.get(ctx, :boards) == {:ok, ModB}
      assert Domain.get(ctx, :threads) == {:ok, ModT}
      assert Domain.get(ctx, :posts) == {:ok, ModP}
      assert Domain.get(ctx, :markdown) == {:ok, ModM}
    end

    test "returns {:error, :not_configured} when ctx is an empty map" do
      assert Domain.get(%{}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when :domain key is absent" do
      assert Domain.get(%{other: :data}, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} when the specific key is absent from :domain" do
      ctx = %{domain: %{threads: SomeThreadsMod}}
      assert Domain.get(ctx, :boards) == {:error, :not_configured}
    end

    test "returns {:error, :not_configured} for unknown keys (no raise)" do
      ctx = %{domain: %{unknown_key: SomeMod}}
      assert Domain.get(ctx, :unknown_key) == {:error, :not_configured}
    end
  end
end
