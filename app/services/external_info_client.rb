require "net/http"
require "json"
require "cgi"

class ExternalInfoClient
  ITUNES_URL = "https://itunes.apple.com/search".freeze
  LYRICS_URL = "https://api.lyrics.ovh/v1".freeze

  def itunes_search(term:, limit: 3, country: "JP")
    params = {
      term: term,
      media: "music",
      entity: "song",
      limit: limit,
      country: country
    }
    get_json(ITUNES_URL, params)
  end

  def lyrics(artist:, title:)
    return { "error" => { "message" => "missing_artist_or_title" } } if artist.blank? || title.blank?

    url = "#{LYRICS_URL}/#{CGI.escape(artist)}/#{CGI.escape(title)}"
    get_json(url)
  end

  private

  def get_json(url, params = nil)
    uri = URI(url)
    uri.query = URI.encode_www_form(params) if params.present?

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = 3
    http.read_timeout = 6

    response = http.get(uri.request_uri)
    body = JSON.parse(response.body)

    return body if response.is_a?(Net::HTTPSuccess)

    body["error"] ||= { "message" => "External API request failed", "status" => response.code }
    body
  rescue JSON::ParserError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    { "error" => { "message" => e.message } }
  end
end
