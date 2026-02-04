require "net/http"
require "json"

class YoutubeClient
  BASE_URL = "https://www.googleapis.com/youtube/v3".freeze

  def initialize(api_key:)
    @api_key = api_key
  end

  def search_videos(query:, max_results: 10, language: nil)
    params = {
      part: "snippet",
      q: query,
      type: "video",
      maxResults: max_results,
      videoEmbeddable: true,
      videoSyndicated: true
    }
    params[:relevanceLanguage] = language if language.present?
    get("/search", params)
  end

  def video_details(video_id:)
    get("/videos", part: "snippet,contentDetails,statistics", id: video_id)
  end

  def channel_details(channel_id:)
    get("/channels", part: "snippet,statistics", id: channel_id)
  end

  private

  def get(path, params)
    uri = URI("#{BASE_URL}#{path}")
    uri.query = URI.encode_www_form(params.merge(key: @api_key))

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 3
    http.read_timeout = 6

    response = http.get(uri.request_uri)
    body = JSON.parse(response.body)

    return body if response.is_a?(Net::HTTPSuccess)

    body["error"] ||= { "message" => "YouTube API request failed", "status" => response.code }
    body
  rescue JSON::ParserError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    { "error" => { "message" => e.message } }
  end
end
