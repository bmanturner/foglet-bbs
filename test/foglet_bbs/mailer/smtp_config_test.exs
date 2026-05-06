defmodule Foglet.Mailer.SMTPConfigTest do
  use ExUnit.Case, async: true

  alias Foglet.Mailer.SMTPConfig

  describe "cacerts_for/1" do
    test "keeps OTP system certificates when they are available" do
      cacerts = [{:OTPCertificate, <<1, 2, 3>>}]

      assert SMTPConfig.cacerts_for(cacerts) == cacerts
    end

    test "falls back to certifi when OTP has no configured system certificates" do
      assert SMTPConfig.cacerts_for(:undefined) == :certifi.cacerts()
    end
  end

  describe "tls_options/1" do
    test "builds peer-verifying TLS options with a concrete CA bundle and SNI" do
      options = SMTPConfig.tls_options("smtp.example.test")

      assert Keyword.fetch!(options, :verify) == :verify_peer
      assert Keyword.fetch!(options, :server_name_indication) == ~c"smtp.example.test"
      assert is_list(Keyword.fetch!(options, :cacerts))
      assert Keyword.fetch!(options, :cacerts) != :undefined
    end
  end
end
