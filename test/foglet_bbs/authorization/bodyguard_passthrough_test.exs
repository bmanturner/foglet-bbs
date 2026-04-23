defmodule Foglet.Authorization.AlwaysForbiddenPolicy do
  @moduledoc false
  @behaviour Bodyguard.Policy

  @impl Bodyguard.Policy
  def authorize(_action, _user, _params), do: {:error, :forbidden}
end

defmodule Foglet.Authorization.BodyguardPassthroughTest do
  @moduledoc """
  A4 smoke test: guards that Bodyguard.permit/4 does not coerce our explicit
  `{:error, :forbidden}` callback return to the default `{:error, :unauthorized}`.
  Catches a hypothetical future Bodyguard release that changes coercion.
  """
  use ExUnit.Case, async: true

  alias Foglet.Authorization.AlwaysForbiddenPolicy

  test "Bodyguard.permit/4 passes {:error, :forbidden} through unchanged (A4)" do
    assert Bodyguard.permit(AlwaysForbiddenPolicy, :x, nil, :y) == {:error, :forbidden}
  end
end
