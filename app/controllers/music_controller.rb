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
    title_parse = parse_title_parts(title)
    artist_sanitized = sanitize_artist(artist)
    if debug
      debug_info[:request] = {
        title: title,
        artist: artist,
        query: query
      }
      debug_info[:title_parse] = title_parse
      debug_info[:artist_sanitized] = artist_sanitized
    end

    if query.blank?
      response = {
        itunes: { items: [] },
        lyrics: nil,
        links: build_links(
          title: title,
          artist: artist_sanitized,
          video_id: params[:video_id].to_s.strip,
          channel_id: params[:channel_id].to_s.strip
        )
      }
      response[:debug] = debug_info if debug
      return render json: response
    end

    itunes_term = sanitize_title(title).presence || query
    itunes_data = external_client.itunes_search(term: itunes_term, limit: 5)
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

    top_item = select_itunes_item(items, title: title, artist: artist_sanitized)
    lyrics_text = nil
    lyrics_debug = { attempts: [] }
    candidates = build_lyrics_candidates(
      title: title,
      artist: artist_sanitized,
      parsed_left: title_parse[:left],
      parsed_right: title_parse[:right],
      itunes_item: top_item
    )

    if candidates.empty?
      lyrics_debug[:status] = "skipped"
      lyrics_debug[:reason] = "no_candidates"
    else
      candidates.each do |candidate|
        attempt = {
          source: candidate[:source],
          artist: candidate[:artist],
          title: candidate[:title],
          url: lyrics_request_url(candidate[:artist], candidate[:title])
        }

        lyrics_data = external_client.lyrics(artist: candidate[:artist], title: candidate[:title])
        if lyrics_data.is_a?(Hash) && lyrics_data["lyrics"].present?
          lyrics_text = lyrics_data["lyrics"]
          attempt[:status] = "ok"
          lyrics_debug[:status] = "ok"
          lyrics_debug[:selected] = {
            source: candidate[:source],
            artist: candidate[:artist],
            title: candidate[:title]
          }
          lyrics_debug[:attempts] << attempt
          break
        else
          attempt[:status] = "error"
          attempt[:error] = lyrics_data["error"] || "no_lyrics"
          lyrics_debug[:attempts] << attempt
        end
      end

      lyrics_debug[:status] ||= "error"
    end

    if debug
      debug_info[:itunes] = {
        count: items.size,
        term: itunes_term,
        top: items.first&.slice(:title, :artist, :album, :release_date, :genre),
        selected: top_item&.slice(:title, :artist, :album, :release_date, :genre)
      }
      debug_info[:lyrics] = lyrics_debug
    end

    response = {
      itunes: { items: items },
      lyrics: lyrics_text.present? ? { text: lyrics_text, source: "lyrics.ovh" } : nil,
      links: build_links(
        title: title,
        artist: artist_sanitized,
        query: query,
        video_id: params[:video_id].to_s.strip,
        channel_id: params[:channel_id].to_s.strip,
        itunes_item: top_item
      )
    }
    response[:debug] = debug_info if debug
    render json: response
  end

  def translate
    text = params[:text].to_s
    return render json: { error: "missing_text" }, status: :bad_request if text.blank?

    source = params[:source].presence || "auto"
    target = params[:target].presence || "ja"

    data = libretranslate_client.translate(text: text, source: source, target: target)
    return render_api_error(data) if api_error?(data)

    render json: {
      text: data["text"],
      detected: data["detected"]
    }
  end

  def playlist
    playlist = find_or_create_playlist
    render json: playlist_payload(playlist)
  end

  def add_to_playlist
    playlist = find_or_create_playlist
    video_id = params[:video_id].to_s.strip
    return render json: { error: "missing_video_id" }, status: :bad_request if video_id.blank?

    item = playlist.playlist_items.find_or_initialize_by(video_id: video_id)
    item.title = params[:title].to_s.strip.presence || "Untitled"
    item.channel_title = params[:channel].to_s.strip

    if item.save
      render json: playlist_payload(playlist)
    else
      render json: { error: item.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def remove_from_playlist
    playlist = find_playlist_by_name
    return render json: { playlist: { name: playlist_name }, items: [] } if playlist.blank?

    video_id = params[:video_id].to_s.strip
    if video_id.present?
      playlist.playlist_items.where(video_id: video_id).delete_all
    else
      playlist.playlist_items.delete_all
    end

    render json: playlist_payload(playlist)
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

  def libretranslate_client
    @libretranslate_client ||= LibreTranslateClient.new
  end

  def api_error?(data)
    data.is_a?(Hash) && data["error"].present?
  end

  def render_api_error(data)
    render json: { error: data["error"] }, status: :bad_gateway
  end

  def playlist_payload(playlist)
    {
      playlist: { id: playlist.id, name: playlist.name },
      items: playlist.playlist_items.order(created_at: :asc).map do |item|
        {
          id: item.id,
          video_id: item.video_id,
          title: item.title,
          channel_title: item.channel_title
        }
      end
    }
  end

  def playlist_name
    name = params[:playlist_name].to_s.strip
    name = "Watch Later" if name.blank?
    name
  end

  def find_playlist_by_name
    Playlist.where("lower(name) = ?", playlist_name.downcase).first
  end

  def find_or_create_playlist
    find_playlist_by_name || Playlist.create!(name: playlist_name)
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

  def parse_title_parts(title)
    cleaned = sanitize_title(title)
    left, right = split_title(cleaned)
    { cleaned: cleaned, left: left, right: right }
  end

  def build_lyrics_candidates(title:, artist:, parsed_left:, parsed_right:, itunes_item:)
    candidates = []

    if parsed_left.present? && parsed_right.present?
      if artist.present?
        if includes_insensitive?(parsed_left, artist)
          candidates << { source: "parsed_title", artist: parsed_left, title: parsed_right }
        elsif includes_insensitive?(parsed_right, artist)
          candidates << { source: "parsed_title", artist: parsed_right, title: parsed_left }
        else
          candidates << { source: "parsed_title", artist: parsed_left, title: parsed_right }
          candidates << { source: "parsed_title_swap", artist: parsed_right, title: parsed_left }
        end
      else
        candidates << { source: "parsed_title", artist: parsed_left, title: parsed_right }
        candidates << { source: "parsed_title_swap", artist: parsed_right, title: parsed_left }
      end
    elsif artist.present? && title.present?
      candidates << { source: "channel_title", artist: artist, title: sanitize_title(title) }
    end

    if itunes_item&.dig(:artist).present? && itunes_item&.dig(:title).present?
      candidates << { source: "itunes", artist: itunes_item[:artist], title: itunes_item[:title] }
    end

    unique_by = {}
    candidates.select do |candidate|
      key = "#{candidate[:artist].to_s.downcase}|#{candidate[:title].to_s.downcase}"
      next false if candidate[:artist].blank? || candidate[:title].blank?
      next false if unique_by[key]
      unique_by[key] = true
      true
    end
  end

  def sanitize_title(title)
    text = title.to_s.dup
    text.gsub!(/\[[^\]]*\]|\([^\)]*\)|\{[^}]*\}/, " ")
    text.gsub!(/(official|lyrics?|mv|pv|music video|live|performance|studio|cover|remaster|hd|4k|visualizer|audio|full|ver\.|version)/i, " ")
    text.gsub!(/\s+/, " ")
    text.strip
  end

  def sanitize_artist(artist)
    text = artist.to_s.dup
    text.gsub!(/\s*-\s*topic\b/i, " ")
    text.gsub!(/\b(topic|vevo|official|channel)\b/i, " ")
    text.gsub!(/\s*[-–—|｜]+\s*$/, " ")
    text.gsub!(/\s+/, " ")
    text.strip
  end

  def split_title(text)
    return [nil, nil] if text.blank?
    match = text.match(/(.+?)\s*(?:-+|–|—|\||｜|\/|:)\s*(.+)/)
    return [match[1].strip, match[2].strip] if match && match[1].present? && match[2].present?
    [nil, nil]
  end

  def includes_insensitive?(text, fragment)
    return false if fragment.blank?
    text.to_s.downcase.include?(fragment.to_s.downcase)
  end

  def select_itunes_item(items, title:, artist:)
    return items.first if items.blank?
    normalized_title = sanitize_title(title).downcase
    normalized_artist = sanitize_artist(artist).downcase

    candidates = items.map do |item|
      score = 0
      item_title = item[:title].to_s.downcase
      item_artist = item[:artist].to_s.downcase
      score += 2 if normalized_title.present? && item_title.include?(normalized_title)
      score += 1 if normalized_artist.present? && item_artist.include?(normalized_artist)
      score -= 2 if normalized_title.present? && !item_title.include?(normalized_title)
      score -= 1 if normalized_artist.present? && !item_artist.include?(normalized_artist)
      { item: item, score: score }
    end

    best = candidates.max_by { |entry| entry[:score] }
    return nil if best[:score] < 1
    best[:item]
  end

  def lyrics_request_url(artist, title)
    "#{ExternalInfoClient::LYRICS_URL}/#{CGI.escape(artist)}/#{CGI.escape(title)}"
  end
end
