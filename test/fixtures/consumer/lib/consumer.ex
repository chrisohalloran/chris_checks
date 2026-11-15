defmodule Consumer do
  @moduledoc "A minimal consumer of chris_checks."
  use Boundary, deps: [], exports: [Pricing]
end
