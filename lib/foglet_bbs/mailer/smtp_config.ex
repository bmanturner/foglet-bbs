defmodule Foglet.Mailer.SMTPConfig do
  @moduledoc """
  Runtime SMTP configuration helpers.
  """

  @doc """
  Builds TLS options for SMTP STARTTLS or SSL connections.
  """
  @spec tls_options(String.t()) :: keyword()
  def tls_options(relay) when is_binary(relay) do
    [
      verify: :verify_peer,
      cacerts: cacerts(),
      server_name_indication: String.to_charlist(relay),
      depth: 4,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  @doc false
  @spec cacerts() :: [public_key: term()]
  def cacerts, do: cacerts_for(:public_key.cacerts_get())

  @doc false
  @spec cacerts_for(:undefined | [term()]) :: [term()]
  def cacerts_for(:undefined), do: :certifi.cacerts()
  def cacerts_for(cacerts) when is_list(cacerts), do: cacerts
end
