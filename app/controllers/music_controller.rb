require "cgi"

class MusicController < ApplicationController
  def index
  end

  def search
    return render json: { error: "missing_api_key" }, status: :service_unavailable if api_key.blank?

    query = params[:q].to_s.strip
    return render json: { items: [] } if query.blank?

    data = youtube_client.search_videos(query: query, max_results: 12, language: "ja")
    return render_api_error(data) if api_error?(data)

    items = Array(data["items"]).map do |item|
      snippet = item["snippet"] || {}
      {
        id: item.dig("id", "videoId"),
        title: snippet["title"],
        channel_id: snippet["channelId"],
        channel_title: snippet["channelTitle"],
        published_at: snippet["publishedAt"],
        thumbnail: snippet.dig("thumbnails", "medium", "url") || snippet.dig("thumbnails", "default", "url")
      }
    end.compact

    render json: { items: items }
  end

  def details
    return render json: { error: "missing_api_key" }, status: :service_unavailable if api_key.blank?

    video_id = params[:video_id].to_s.strip
    return render json: { error: "missing_video_id" }, status: :bad_request if video_id.blank?

    video_data = youtube_client.video_details(video_id: video_id)
    return render_api_error(video_data) if api_error?(video_data)

    video = Array(video_data["items"]).first
    return render json: { error: "not_found" }, status: :not_found if video.blank?

    channel_id = video.dig("snippet", "channelId")
    channel_data = channel_id.present? ? youtube_client.channel_details(channel_id: channel_id) : nil
    channel = channel_data && !api_error?(channel_data) ? Array(channel_data["items"]).first : nil

    render json: {
      video: {
        id: video["id"],
        title: video.dig("snippet", "title"),
        description: video.dig("snippet", "description"),
        published_at: video.dig("snippet", "publishedAt"),
        channel_id: channel_id,
        channel_title: video.dig("snippet", "channelTitle"),
        duration: video.dig("contentDetails", "duration"),
        view_count: video.dig("statistics", "viewCount"),
        like_count: video.dig("statistics", "likeCount")
      },
      channel: channel && {
        id: channel["id"],
        title: channel.dig("snippet", "title"),
        description: channel.dig("snippet", "description"),
        subscribers: channel.dig("statistics", "subscriberCount"),
        view_count: channel.dig("statistics", "viewCount"),
        thumbnail: channel.dig("snippet", "thumbnails", "default", "url")
      }
    }
  end

  def external
    debug = debug_mode?
    debug_info = {}

    title = params[:title].to_s.strip
    artist = params[:artist].to_s.strip
    query = params[:q].to_s.strip
    query = [title, artist].join(" ").strip if query.blank?
    if debug
      debug_info[:request] = {
        title: title,
        artist: artist,
        query: query
      }
    end

    if query.blank?
      response = {
        itunes: { items: [] },
        lyrics: nil,
        links: build_links(
          title: title,
          artist: artist,
          video_id: params[:video_id].to_s.strip,
          channel_id: params[:channel_id].to_s.strip
        )
      }
      response[:debug] = debug_info if debug
      return render json: response
    end

    itunes_data = external_client.itunes_search(term: query, limit: 3)
    return render_api_error(itunes_data) if api_error?(itunes_data)

    items = Array(itunes_data["results"]).map do |item|
      artwork = item["artworkUrl100"]
      {
        title: item["trackName"],
        artist: item["artistName"],
        album: item["collectionName"],
        release_date: item["releaseDate"],
        genre: item["primaryGenreName"],
        artwork: artwork&.gsub("100x100", "300x300"),
        preview_url: item["previewUrl"],
        track_url: item["trackViewUrl"],
        artist_url: item["artistViewUrl"],
        album_url: item["collectionViewUrl"],
        track_time_ms: item["trackTimeMillis"]
      }
    end

    top_item = items.first
    lyrics_text = nil
    lyrics_debug = {}
    if top_item&.dig(:artist).present? && top_item&.dig(:title).present?
      lyrics_data = external_client.lyrics(artist: top_item[:artist], title: top_item[:title])
      if lyrics_data.is_a?(Hash) && lyrics_data["lyrics"].present?
        lyrics_text = lyrics_data["lyrics"]
        lyrics_debug[:status] = "ok"
      else
        lyrics_debug[:status] = "error"
        lyrics_debug[:error] = lyrics_data["error"] || "no_lyrics"
      end
    else
      lyrics_debug[:status] = "skipped"
      lyrics_debug[:reason] = "no_itunes_match"
    end

    if debug
      debug_info[:itunes] = {
        count: items.size,
        top: top_item&.slice(:title, :artist, :album, :release_date, :genre)
      }
      debug_info[:lyrics] = lyrics_debug
    end

    response = {
      itunes: { items: items },
      lyrics: lyrics_text.present? ? { text: lyrics_text, source: "lyrics.ovh" } : nil,
      links: build_links(
        title: title,
        artist: artist,
        query: query,
        video_id: params[:video_id].to_s.strip,
        channel_id: params[:channel_id].to_s.strip,
        itunes_item: top_item
      )
    }
    response[:debug] = debug_info if debug
    render json: response
  end

  private

  def youtube_client
    @youtube_client ||= YoutubeClient.new(api_key: api_key)
  end

  def api_key
    ENV["YOUTUBE_API_KEY"]
  end

  def external_client
    @external_client ||= ExternalInfoClient.new
  end

  def api_error?(data)
    data.is_a?(Hash) && data["error"].present?
  end

  def render_api_error(data)
    render json: { error: data["error"] }, status: :bad_gateway
  end

  def build_links(title:, artist:, query: nil, video_id: nil, channel_id: nil, itunes_item: nil)
    links = []
    if video_id.present?
      links << { label: "YouTube", url: "https://www.youtube.com/watch?v=#{video_id}" }
    end
    if channel_id.present?
      links << { label: "Channel", url: "https://www.youtube.com/channel/#{channel_id}" }
    end
    if itunes_item&.dig(:track_url).present?
      links << { label: "Apple Music", url: itunes_item[:track_url] }
    end

    wiki_term = itunes_item&.dig(:artist).presence || artist.presence || title.presence || query.to_s
    if wiki_term.present?
      links << {
        label: "Wikipedia",
        url: "https://ja.wikipedia.org/wiki/Special:Search?search=#{CGI.escape(wiki_term)}"
      }
    end

    review_term = [itunes_item&.dig(:title).presence || title.presence, itunes_item&.dig(:artist).presence || artist.presence]
                  .compact.join(" ").strip
    if review_term.present?
      links << {
        label: "レビュー検索",
        url: "https://duckduckgo.com/?q=#{CGI.escape("#{review_term} レビュー")}"
      }
    end
    links
  end

  def debug_mode?
    Rails.env.development? || params[:debug].to_s == "1"
  end
end
