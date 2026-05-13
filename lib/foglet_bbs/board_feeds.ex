defmodule Foglet.BoardFeeds do
  @moduledoc """
  Board-scoped RSS/Atom feed configuration, safe fetching, and cached item reads.

  Network fetches are explicit context effects and are never required by renderers.
  Callers can pass `fetcher: fun` in tests/background jobs; the default fetcher is
  bounded to http/https URLs that pass the local/private-host guard.
  """

  import Ecto.Query, except: [first: 2]

  alias Foglet.BoardFeeds.{Feed, Item}
  alias FogletBbs.Repo

  @authorization Foglet.Authorization
  @max_response_bytes 1_000_000
  @retention_per_feed 200

  defmodule FetchResult do
    @moduledoc "Bounded feed fetch result."
    defstruct [:url, :body]
  end

  def create_feed(actor, board_id, attrs, opts \\ []) do
    with :ok <- Bodyguard.permit(@authorization, :manage_board_feeds, actor, {:board, board_id}),
         {:ok, url} <- safe_url(Map.get(attrs, :url) || Map.get(attrs, "url")),
         {:ok, %FetchResult{url: final_url, body: body}} <- fetch(url, opts),
         {:ok, parsed} <- parse_feed(body) do
      now = now()

      Repo.transact(fn ->
        feed_attrs = %{
          board_id: board_id,
          url: final_url,
          title: parsed.title,
          enabled: Map.get(attrs, :enabled, Map.get(attrs, "enabled", true)),
          display_order: Map.get(attrs, :display_order, Map.get(attrs, "display_order", 0)),
          cache_ttl_seconds:
            Map.get(attrs, :cache_ttl_seconds, Map.get(attrs, "cache_ttl_seconds", 3600)),
          last_fetched_at: now,
          last_success_at: now,
          last_error: nil
        }

        case %Feed{} |> Feed.changeset(feed_attrs) |> Repo.insert() do
          {:ok, feed} ->
            upsert_items(feed, parsed.items, now)
            {:ok, Repo.preload(feed, :items)}

          {:error, changeset} ->
            {:error, changeset}
        end
      end)
    end
  end

  def list_feeds(actor, board_id) do
    if can_read_board?(actor, board_id) do
      Feed
      |> where([f], f.board_id == ^board_id)
      |> order_by([f], asc: f.display_order, asc: f.inserted_at)
      |> Repo.all()
    else
      []
    end
  end

  def list_cached_items(actor, board_id, opts \\ []) do
    if can_read_board?(actor, board_id) do
      limit = Keyword.get(opts, :limit, 50)

      Item
      |> join(:inner, [i], f in assoc(i, :feed))
      |> where([i, f], i.board_id == ^board_id and f.enabled == true)
      |> order_by([i], desc_nulls_last: i.published_at, desc: i.fetched_at)
      |> limit(^limit)
      |> preload(:feed)
      |> Repo.all()
    else
      []
    end
  end

  def enabled_feed_count(board_id) do
    Feed
    |> where([f], f.board_id == ^board_id and f.enabled == true)
    |> Repo.aggregate(:count)
  end

  def refresh_feed(actor, feed_id, opts \\ []) do
    feed = Repo.get!(Feed, feed_id)

    with :ok <-
           Bodyguard.permit(@authorization, :manage_board_feeds, actor, {:board, feed.board_id}) do
      if fresh?(feed) and not Keyword.get(opts, :force, false) do
        {:ok, :fresh}
      else
        refresh_feed_record(feed, opts)
      end
    end
  end

  def refresh_board(actor, board_id, opts \\ []) do
    with :ok <- Bodyguard.permit(@authorization, :manage_board_feeds, actor, {:board, board_id}) do
      Feed
      |> where([f], f.board_id == ^board_id and f.enabled == true)
      |> Repo.all()
      |> Enum.map(&refresh_feed_record(&1, opts))
    end
  end

  def safe_url(url) when is_binary(url) do
    url = String.trim(url)

    with true <- byte_size(url) in 1..2048,
         %URI{scheme: scheme, host: host, userinfo: nil} = uri <- URI.parse(url),
         true <- scheme in ["http", "https"],
         true <- is_binary(host) and host != "",
         false <- unsafe_host?(host) do
      {:ok, URI.to_string(uri)}
    else
      _ -> {:error, :unsafe_url}
    end
  end

  def safe_url(_), do: {:error, :unsafe_url}

  def parse_feed(body) when is_binary(body) do
    cond do
      Regex.match?(~r/<rss[\s>]/i, body) -> parse_rss(body)
      Regex.match?(~r/<feed[\s>]/i, body) -> parse_atom(body)
      true -> {:error, :invalid_feed}
    end
  rescue
    _ -> {:error, :invalid_feed}
  end

  def sanitize_display(nil, _max), do: nil

  def sanitize_display(text, max) when is_binary(text) do
    text
    |> html_unescape()
    |> String.replace(~r/\e\[[0-?]*[ -\/]*[@-~]/u, "")
    |> String.replace(~r/<[^>]*>/u, "")
    |> String.replace(~r/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\x9B]/u, "")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> String.slice(0, max)
  end

  defp refresh_feed_record(feed, opts) do
    now = now()

    with {:ok, %FetchResult{body: body}} <- fetch(feed.url, opts),
         {:ok, parsed} <- parse_feed(body) do
      Repo.transact(fn ->
        {:ok, _} =
          feed
          |> Feed.changeset(%{
            title: parsed.title,
            last_fetched_at: now,
            last_success_at: now,
            last_error: nil
          })
          |> Repo.update()

        upsert_items(feed, parsed.items, now)
        trim_items(feed.id)
        {:ok, :refreshed}
      end)
    else
      {:error, reason} ->
        feed
        |> Feed.changeset(%{last_fetched_at: now, last_error: inspect(reason)})
        |> Repo.update()

        {:error, reason}
    end
  end

  defp fetch(url, opts) do
    fetcher = Keyword.get(opts, :fetcher, &default_fetcher/1)

    with {:ok, safe} <- safe_url(url),
         {:ok, %FetchResult{url: final_url} = result} <- fetcher.(safe),
         {:ok, final_safe} <- safe_url(final_url),
         true <- byte_size(result.body || "") <= @max_response_bytes do
      {:ok, %{result | url: final_safe}}
    else
      false -> {:error, :response_too_large}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :fetch_failed}
    end
  end

  defp default_fetcher(url) do
    :inets.start()
    :ssl.start()

    request = {String.to_charlist(url), []}
    http_opts = [timeout: 5_000, connect_timeout: 3_000, autoredirect: true, max_redirect: 3]
    opts = [body_format: :binary]

    case :httpc.request(:get, request, http_opts, opts) do
      {:ok, {{_, status, _}, _headers, body}} when status in 200..299 ->
        {:ok,
         %FetchResult{
           url: url,
           body: binary_part(body, 0, min(byte_size(body), @max_response_bytes + 1))
         }}

      {:ok, {{_, status, _}, _headers, _body}} ->
        {:error, {:http_status, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_rss(body) do
    title =
      body |> first(~r/<channel[^>]*>.*?<title[^>]*>(.*?)<\/title>/isu) |> sanitize_display(200)

    items =
      for block <- Regex.scan(~r/<item[\s>].*?<\/item>/isu, body),
          do: parse_rss_item(List.first(block))

    valid_items = Enum.reject(items, &is_nil/1)

    if title in [nil, ""] or valid_items == [] do
      {:error, :invalid_feed}
    else
      {:ok, %{title: title, items: dedupe_items(valid_items)}}
    end
  end

  defp parse_rss_item(block) do
    title = block |> first(~r/<title[^>]*>(.*?)<\/title>/isu) |> sanitize_display(300)
    link = block |> first(~r/<link[^>]*>(.*?)<\/link>/isu) |> sanitize_display(2048)
    guid = block |> first(~r/<guid[^>]*>(.*?)<\/guid>/isu) |> sanitize_display(500)

    summary =
      block |> first(~r/<description[^>]*>(.*?)<\/description>/isu) |> sanitize_display(1000)

    author = block |> first(~r/<author[^>]*>(.*?)<\/author>/isu) |> sanitize_display(120)
    published_at = block |> first(~r/<pubDate[^>]*>(.*?)<\/pubDate>/isu) |> parse_date()
    build_item(title, link, guid, summary, author, published_at)
  end

  defp parse_atom(body) do
    title = body |> first(~r/<title[^>]*>(.*?)<\/title>/isu) |> sanitize_display(200)

    items =
      for block <- Regex.scan(~r/<entry[\s>].*?<\/entry>/isu, body),
          do: parse_atom_item(List.first(block))

    valid_items = Enum.reject(items, &is_nil/1)

    if title in [nil, ""] or valid_items == [] do
      {:error, :invalid_feed}
    else
      {:ok, %{title: title, items: dedupe_items(valid_items)}}
    end
  end

  defp parse_atom_item(block) do
    title = block |> first(~r/<title[^>]*>(.*?)<\/title>/isu) |> sanitize_display(300)

    link =
      (block |> first(~r/<link[^>]*href=["']([^"']+)["'][^>]*\/?>/isu) ||
         first(block, ~r/<link[^>]*>(.*?)<\/link>/isu))
      |> sanitize_display(2048)

    guid = block |> first(~r/<id[^>]*>(.*?)<\/id>/isu) |> sanitize_display(500)

    summary =
      (block |> first(~r/<summary[^>]*>(.*?)<\/summary>/isu) ||
         first(block, ~r/<content[^>]*>(.*?)<\/content>/isu))
      |> sanitize_display(1000)

    author =
      block
      |> first(~r/<author[^>]*>.*?<name[^>]*>(.*?)<\/name>.*?<\/author>/isu)
      |> sanitize_display(120)

    published_at =
      (block |> first(~r/<published[^>]*>(.*?)<\/published>/isu) ||
         first(block, ~r/<updated[^>]*>(.*?)<\/updated>/isu))
      |> parse_date()

    build_item(title, link, guid, summary, author, published_at)
  end

  defp build_item(title, link, guid, summary, author, published_at) do
    if title in [nil, ""] do
      nil
    else
      identity =
        guid || link ||
          :crypto.hash(:sha256, title <> (summary || "")) |> Base.encode16(case: :lower)

      %{
        external_id: identity,
        title: title,
        url: link,
        summary: summary,
        author: author,
        published_at: normalize_datetime(published_at)
      }
    end
  end

  defp upsert_items(feed, items, fetched_at) do
    rows =
      Enum.map(items, fn item ->
        item
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          board_feed_id: feed.id,
          board_id: feed.board_id,
          fetched_at: fetched_at,
          inserted_at: fetched_at,
          updated_at: fetched_at,
          metadata: %{}
        })
      end)

    Repo.insert_all(Item, rows,
      on_conflict:
        {:replace, [:title, :url, :author, :summary, :published_at, :fetched_at, :updated_at]},
      conflict_target: [:board_feed_id, :external_id]
    )
  end

  defp trim_items(feed_id) do
    stale_ids =
      Item
      |> where([i], i.board_feed_id == ^feed_id)
      |> order_by([i], desc_nulls_last: i.published_at, desc: i.fetched_at)
      |> offset(^@retention_per_feed)
      |> select([i], i.id)

    Item |> where([i], i.id in subquery(stale_ids)) |> Repo.delete_all()
  end

  defp fresh?(%Feed{last_fetched_at: nil}), do: false

  defp fresh?(%Feed{last_fetched_at: last, cache_ttl_seconds: ttl}) do
    DateTime.compare(DateTime.add(last, ttl, :second), now()) == :gt
  end

  defp can_read_board?(%{role: role, status: :active, deleted_at: nil}, _board_id)
       when role in [:user, :mod, :sysop], do: true

  defp can_read_board?(_, _), do: false

  defp unsafe_host?(host) do
    down = String.downcase(host)

    cond do
      down in ["localhost", "localhost.localdomain"] -> true
      String.ends_with?(down, ".local") -> true
      true -> unsafe_resolved_host?(down)
    end
  end

  defp unsafe_resolved_host?(host) do
    case :inet.getaddrs(String.to_charlist(host), :inet) do
      {:ok, addresses} -> Enum.any?(addresses, &private_ipv4?/1)
      _ -> true
    end
  end

  defp private_ipv4?({10, _, _, _}), do: true
  defp private_ipv4?({127, _, _, _}), do: true
  defp private_ipv4?({169, 254, _, _}), do: true
  defp private_ipv4?({172, second, _, _}) when second in 16..31, do: true
  defp private_ipv4?({192, 168, _, _}), do: true
  defp private_ipv4?({0, _, _, _}), do: true
  defp private_ipv4?({100, second, _, _}) when second in 64..127, do: true
  defp private_ipv4?({_, _, _, _}), do: false

  defp first(text, regex) do
    case Regex.run(regex, text, capture: :all_but_first) do
      [value | _] -> strip_cdata(value)
      _ -> nil
    end
  end

  defp strip_cdata(text),
    do: text |> String.replace(~r/^\s*<!\[CDATA\[/, "") |> String.replace(~r/\]\]>\s*$/, "")

  defp dedupe_items(items), do: Enum.uniq_by(items, & &1.external_id)

  defp normalize_datetime(nil), do: nil
  defp normalize_datetime(%DateTime{} = dt), do: %{dt | microsecond: {elem(dt.microsecond, 0), 6}}

  defp parse_date(nil), do: nil

  defp parse_date(value) do
    with {:error, _} <- DateTime.from_iso8601(value),
         {:ok, parsed} <- Timex.parse(value, "{RFC1123}") do
      parsed |> Timex.to_datetime("Etc/UTC") |> DateTime.truncate(:microsecond)
    else
      {:ok, dt, _} -> DateTime.truncate(dt, :microsecond)
      _ -> nil
    end
  end

  defp html_unescape(text) do
    text
    |> String.replace("&amp;", "&")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&quot;", "\"")
    |> String.replace("&#39;", "'")
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:microsecond)
end
