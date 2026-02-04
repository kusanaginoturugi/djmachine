require "net/http"
require "json"

class LibreTranslateClient
  DEFAULT_URL = "http://localhost:65000".freeze

  def initialize(base_url: ENV.fetch("LIBRETRANSLATE_URL", DEFAULT_URL))
    @base_url = base_url
  end

  def translate(text:, source: "auto", target: "ja", format: "text")
    return { "error" => { "message" => "missing_text" } } if text.blank?

    chunks = split_text(text, max_chars: 800)
    translated_chunks = []
    detected_lang = nil

    chunks.each do |chunk|
      result = translate_chunk(text: chunk, source: source, target: target, format: format)
      return result if result["error"].present?

      translated_chunks << result["text"].to_s
      detected_lang ||= result["detected"]
    end

    {
      "text" => translated_chunks.join("\n"),
      "detected" => detected_lang
    }
  end

  private

  def translate_chunk(text:, source:, target:, format:)
    uri = URI.parse(@base_url).merge("/translate")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 3
    http.read_timeout = 10

    request = Net::HTTP::Post.new(uri)
    request["Content-Type"] = "application/json"
    request.body = JSON.generate({
      q: text,
      source: source,
      target: target,
      format: format
    })

    response = http.request(request)
    body = JSON.parse(response.body)

    return { "text" => body["translatedText"], "detected" => body["detectedLanguage"] } if response.is_a?(Net::HTTPSuccess)

    body["error"] ||= { "message" => "LibreTranslate request failed", "status" => response.code }
    body
  rescue JSON::ParserError, Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout => e
    { "error" => { "message" => e.message } }
  end

  def split_text(text, max_chars:)
    lines = text.to_s.split(/\r?\n/)
    return [text.to_s] if lines.empty?

    chunks = []
    current = []
    current_len = 0

    lines.each do |line|
      line_length = line.length + (current.empty? ? 0 : 1)
      if current_len + line_length > max_chars && current.any?
        chunks << current.join("\n")
        current = [line]
        current_len = line.length
      else
        current << line
        current_len += line_length
      end
    end

    chunks << current.join("\n") if current.any?
    chunks
  end
end
