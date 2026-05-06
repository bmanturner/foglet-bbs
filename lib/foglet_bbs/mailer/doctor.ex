defmodule Foglet.Mailer.Doctor do
  @moduledoc """
  Release-safe transactional email diagnostics.

  This module is intentionally callable without Mix so operators can run it
  inside an OTP release with `/app/bin/foglet_bbs eval`.
  """

  require Logger

  import Swoosh.Email

  alias Foglet.Config
  alias Foglet.Mailer

  @default_from_address "no-reply@localhost"

  @type result :: {:ok, :dry_run | term()} | {:error, term()}

  @doc """
  Print mailer configuration diagnostics and optionally send a test email.

  Options:

    * `:to` - optional recipient address. When omitted, no delivery is
      attempted.
    * `:start_app` - defaults to true. Tests may set it to false when the app
      is already started.
  """
  @spec run(keyword()) :: result()
  def run(opts \\ []) when is_list(opts) do
    if Keyword.get(opts, :start_app, true), do: start_app!()

    mailer_config = Application.get_env(:foglet_bbs, Mailer, [])
    adapter = Keyword.get(mailer_config, :adapter)
    delivery_mode = delivery_mode()
    recipient = opts |> Keyword.get(:to) |> normalize_blank()

    print_header()
    print_runtime_config(mailer_config, adapter, delivery_mode)

    case recipient do
      nil ->
        IO.puts("")
        IO.puts("No --to recipient supplied; this was a dry run. No email was sent.")
        {:ok, :dry_run}

      to ->
        deliver_test_email(to, adapter, delivery_mode)
    end
  end

  defp start_app! do
    {:ok, _} = Application.ensure_all_started(:foglet_bbs)
    :ok
  end

  defp print_header do
    IO.puts("Foglet mailer doctor")
    IO.puts("=====================")
  end

  defp print_runtime_config(mailer_config, adapter, delivery_mode) do
    IO.puts("delivery_mode: #{delivery_mode}")
    IO.puts("adapter: #{inspect(adapter)}")
    IO.puts("mail_from: #{mail_from_address()}#{mail_from_source()}")

    if adapter == Swoosh.Adapters.SMTP or smtp_config_present?(mailer_config) do
      if adapter != Swoosh.Adapters.SMTP do
        IO.puts("smtp: config present, but adapter is not Swoosh.Adapters.SMTP")
      end

      IO.puts("smtp_relay: #{inspect(Keyword.get(mailer_config, :relay))}")
      IO.puts("smtp_port: #{inspect(Keyword.get(mailer_config, :port))}")
      IO.puts("smtp_ssl: #{inspect(Keyword.get(mailer_config, :ssl))}")
      IO.puts("smtp_tls: #{inspect(Keyword.get(mailer_config, :tls))}")
      IO.puts("smtp_auth: #{inspect(Keyword.get(mailer_config, :auth))}")
      IO.puts("smtp_username: #{presence(Keyword.get(mailer_config, :username))}")
      IO.puts("smtp_password: #{presence(Keyword.get(mailer_config, :password))}")
    else
      IO.puts("smtp: not active; set FOGLET_SMTP_RELAY or FOGLET_SMTP_HOST before boot.")
    end
  end

  defp deliver_test_email(_to, _adapter, "no_email") do
    IO.puts("")
    IO.puts("Delivery skipped: delivery_mode is no_email.")
    {:error, :delivery_mode_no_email}
  end

  defp deliver_test_email(to, adapter, delivery_mode) do
    IO.puts("")
    IO.puts("Sending diagnostic email to #{to}...")

    email =
      new()
      |> to({"Foglet mailer doctor", to})
      |> from({"Foglet BBS", mail_from_address()})
      |> subject("Foglet mailer doctor")
      |> text_body("""
      This is a Foglet mailer diagnostic email.

      It was sent by an operator from the mailer doctor task. No account tokens,
      verification codes, reset tokens, passwords, or SSH key material are in
      this message.
      """)

    case Mailer.deliver(email) do
      {:ok, delivery} ->
        IO.puts("Delivery accepted by #{inspect(adapter)}.")
        {:ok, delivery}

      {:error, reason} ->
        log_delivery_failure(adapter, delivery_mode, reason)
        IO.puts("Delivery failed.")
        IO.puts("Reason: #{inspect(reason)}")
        {:error, reason}
    end
  rescue
    exception ->
      reason = {:delivery_exception, exception.__struct__}
      log_delivery_failure(adapter, delivery_mode, reason)
      IO.puts("Delivery raised an exception.")
      IO.puts("Exception: #{inspect(exception.__struct__)}")
      {:error, reason}
  catch
    kind, value ->
      reason = {:delivery_failed, kind, reason_class(value)}
      log_delivery_failure(adapter, delivery_mode, reason)
      IO.puts("Delivery failed with #{inspect(kind)}.")
      IO.puts("Reason class: #{inspect(reason_class(value))}")
      {:error, reason}
  end

  defp log_delivery_failure(adapter, delivery_mode, reason) do
    Logger.error(
      [
        "mailer_doctor_delivery_failed",
        "adapter=#{safe_value(adapter)}",
        "delivery_mode=#{safe_value(delivery_mode)}",
        "reason_class=#{safe_value(reason_class(reason))}"
      ]
      |> Enum.join(" ")
    )
  end

  defp delivery_mode do
    Config.delivery_mode()
  rescue
    _ -> "unavailable"
  end

  defp mail_from_address do
    Application.get_env(:foglet_bbs, :mail_from, @default_from_address)
  end

  defp mail_from_source do
    if Application.get_env(:foglet_bbs, :mail_from) do
      " (configured)"
    else
      " (default)"
    end
  end

  defp normalize_blank(value) when is_binary(value) do
    value = String.trim(value)
    if value == "", do: nil, else: value
  end

  defp normalize_blank(_value), do: nil

  defp smtp_config_present?(mailer_config) do
    Enum.any?([:relay, :port, :ssl, :tls, :auth, :username, :password], fn key ->
      Keyword.has_key?(mailer_config, key)
    end)
  end

  defp presence(nil), do: "unset"
  defp presence(""), do: "unset"
  defp presence(_value), do: "set"

  defp reason_class(%module{}) when is_atom(module), do: module
  defp reason_class(value) when is_atom(value), do: value
  defp reason_class(value) when is_tuple(value) and tuple_size(value) > 0, do: elem(value, 0)
  defp reason_class(value) when is_binary(value), do: :binary
  defp reason_class(_value), do: :unknown

  defp safe_value(nil), do: "nil"
  defp safe_value(value) when is_atom(value), do: Atom.to_string(value)
  defp safe_value(value) when is_binary(value), do: value
  defp safe_value(value), do: inspect(value)
end
