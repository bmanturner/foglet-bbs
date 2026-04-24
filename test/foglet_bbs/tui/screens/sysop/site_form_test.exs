defmodule Foglet.TUI.Screens.Sysop.SiteFormTest do
  use FogletBbs.DataCase, async: false

  import Foglet.TUI.RenderHelpers

  alias Foglet.Config
  alias Foglet.Config.Schema
  alias Foglet.TUI.Screens.Sysop.SiteForm
  alias Foglet.TUI.Theme

  @config_keys Map.keys(Schema.defaults())

  setup do
    Config.init_cache()
    for key <- @config_keys, do: Config.invalidate(key)

    for {key, default} <- Schema.defaults() do
      Config.put!(key, default, nil)
    end

    on_exit(fn -> for key <- @config_keys, do: Config.invalidate(key) end)

    :ok
  end

  describe "delivery mode placement" do
    test "site_keys places delivery_mode before require_email_verification" do
      assert SiteForm.site_keys() == [
               "registration_mode",
               "invite_code_generators",
               "delivery_mode",
               "require_email_verification",
               "invite_generation_per_user_limit"
             ]
    end

    test "init loads delivery_mode draft from Config" do
      Config.put!("delivery_mode", "email", nil)

      form = SiteForm.init([])

      assert form.drafts["delivery_mode"] == "email"
    end

    test "render shows delivery_mode description and current value" do
      Config.put!("delivery_mode", "email", nil)

      text =
        SiteForm.init([])
        |> SiteForm.render(Theme.default())
        |> collect_text_values()
        |> Enum.join("\n")

      assert text =~ "delivery_mode: email"
      assert text =~ "Outbound transactional delivery mode"
    end

    test "enum first-character input selects email and no_email" do
      form = SiteForm.init([])
      delivery_index = Enum.find_index(SiteForm.visible_keys(form), &(&1 == "delivery_mode"))
      form = %{form | focused: delivery_index}

      {form, []} = SiteForm.handle_key(%{key: :char, char: "e"}, form)
      assert form.drafts["delivery_mode"] == "email"

      {form, []} = SiteForm.handle_key(%{key: :char, char: "n"}, form)
      assert form.drafts["delivery_mode"] == "no_email"
    end
  end
end
