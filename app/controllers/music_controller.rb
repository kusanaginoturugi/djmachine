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

  private

  def youtube_client
    @youtube_client ||= YoutubeClient.new(api_key: api_key)
  end

  def api_key
    ENV["YOUTUBE_API_KEY"]
  end

  def api_error?(data)
    data.is_a?(Hash) && data["error"].present?
  end

  def render_api_error(data)
    render json: { error: data["error"] }, status: :bad_gateway
  end
end
