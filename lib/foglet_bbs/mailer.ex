defmodule Foglet.Mailer do
  @moduledoc """
  Swoosh mailer boundary for Foglet transactional delivery.
  """

  use Swoosh.Mailer, otp_app: :foglet_bbs
end
