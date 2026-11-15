defmodule Consumer.PricingTest do
  use ExUnit.Case, async: true

  test "sums the prices" do
    assert Consumer.Pricing.total([%{price: 2}, %{price: 3}]) == 5
  end
end
