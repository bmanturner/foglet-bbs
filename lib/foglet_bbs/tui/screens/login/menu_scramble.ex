defmodule Foglet.TUI.Screens.Login.MenuScramble do
  @moduledoc """
  Login-menu vanity animation owner (D-13, D-14, D-16).

  The scramble-text widget remains stateless (D-16); this module owns the
  login menu's target text, widget options, frame state helpers, tick update,
  render helper, and interval subscription metadata. Keeping the vanity
  animation here preserves Login's screen ownership (D-13/D-14) without
  leaking login-specific timing into the App subscription shell.
  """

  alias Foglet.TUI.Theme
  alias Foglet.TUI.Widgets.Display.ScrambleText

  @targets ["you are outside.", "knock or hang up."]
  @opts [
    charset: :mixed,
    direction: :left_to_right,
    cursor: nil,
    reveal_rate: 2,
    settle_duration: nil,
    seed: nil
  ]
  @frame_key :menu_scramble_frame
  @tick_message :login_menu_scramble_tick

  @type interval_subscription :: {100, :login_menu_scramble_tick}

  @doc "Returns the default frame value for login menu state."
  def default_frame, do: 0

  @doc "Returns the login menu scramble frame from local state."
  @spec frame(map()) :: non_neg_integer()
  def frame(local_state) when is_map(local_state),
    do: Map.get(local_state, @frame_key, default_frame())

  @doc "Writes the login menu scramble frame into local state."
  def put_frame(local_state, frame)
      when is_map(local_state) and is_integer(frame) and frame >= 0 do
    Map.put(local_state, @frame_key, frame)
  end

  @doc "Returns true while the menu scramble animation has frames to advance."
  @spec active?(map()) :: boolean()
  def active?(local_state) when is_map(local_state) do
    Map.get(local_state, :sub, :menu) == :menu and frame(local_state) < settled_frame()
  end

  def active?(_local_state), do: false

  @doc "Advances the login menu scramble frame when the menu animation is active."
  @spec tick(map()) :: map()
  def tick(local_state) when is_map(local_state) do
    if active?(local_state) do
      put_frame(local_state, min(frame(local_state) + 1, settled_frame()))
    else
      local_state
    end
  end

  @doc "Renders the two menu scramble lines for the current frame."
  @spec render(map(), Theme.t()) :: [term()]
  def render(local_state, %Theme{} = theme) when is_map(local_state) do
    current_frame = frame(local_state)
    opts = widget_opts(theme)

    Enum.map(@targets, &ScrambleText.render(&1, current_frame, opts))
  end

  @doc "Returns screen-owned interval metadata while the menu scramble is active."
  def subscriptions(local_state) do
    if active?(local_state), do: [interval_subscription()], else: []
  end

  @doc "Returns the interval metadata consumed by App.Subscriptions."
  def interval_subscription, do: {ScrambleText.frame_duration_ms(), @tick_message}

  @doc "Returns the first fully settled frame across the menu targets."
  @spec settled_frame() :: non_neg_integer()
  def settled_frame do
    @targets
    |> Enum.map(&ScrambleText.settled_frame(&1, widget_opts()))
    |> Enum.max()
  end

  defp widget_opts(theme \\ nil) do
    @opts
    |> Keyword.reject(fn {_key, value} -> is_nil(value) end)
    |> maybe_put_theme(theme)
  end

  defp maybe_put_theme(opts, nil), do: opts
  defp maybe_put_theme(opts, %Theme{} = theme), do: Keyword.put(opts, :theme, theme)
end
