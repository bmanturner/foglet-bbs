defmodule FogletBbs.Repo do
  use Ecto.Repo,
    otp_app: :foglet_bbs,
    adapter: Ecto.Adapters.Postgres
end
