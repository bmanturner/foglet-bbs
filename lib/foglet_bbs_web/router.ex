defmodule FogletBbsWeb.Router do
  use FogletBbsWeb, :router

  @csp "default-src 'self'; " <>
         "script-src 'self'; " <>
         "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; " <>
         "font-src 'self' https://fonts.gstatic.com; " <>
         "img-src 'self'; " <>
         "connect-src 'self'; " <>
         "base-uri 'self'; " <>
         "form-action 'self'; " <>
         "frame-ancestors 'none'; " <>
         "object-src 'none'"

  pipeline :browser do
    plug :accepts, ["html"]
    plug :put_secure_browser_headers, %{"content-security-policy" => @csp}
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", FogletBbsWeb do
    pipe_through :browser

    get "/", PageController, :home

    get "/docs", DocsController, :index
    get "/docs/:category/:id", DocsController, :show
  end

  scope "/" do
    get "/up", FogletBbsWeb.HealthController, :index
  end

  scope "/api", FogletBbsWeb do
    pipe_through :api
  end

  # Enable LiveDashboard in development
  if Application.compile_env(:foglet_bbs, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through [:fetch_session, :protect_from_forgery]

      live_dashboard "/dashboard", metrics: FogletBbsWeb.Telemetry
    end
  end
end
