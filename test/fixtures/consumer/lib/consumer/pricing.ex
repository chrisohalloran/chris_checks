defmodule Consumer.Pricing do
  @moduledoc "Totals for a list of line items."

  def total(items), do: items |> Enum.map(& &1.price) |> Enum.sum()
end
