import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    debug: Boolean
  }

  static targets = [
    "query",
    "results",
    "player",
    "playlist",
    "nowPlaying",
    "trackInfo",
    "channelInfo",
    "externalInfo",
    "autoplayNotice",
    "status"
  ]

  connect() {
    this.playlistItems = []
    this.playerReady = false
    this.loadYouTubeApi().then((YT) => this.buildPlayer(YT))
  }

  disconnect() {
    if (this.player && this.player.destroy) {
      this.player.destroy()
    }
  }

  async search(event) {
    event.preventDefault()
    const query = this.queryTarget.value.trim()
    if (!query) return

    this.setStatus("検索中...", "busy")
    try {
      const response = await fetch(`/music/search?q=${encodeURIComponent(query)}`)
      const data = await response.json()
      if (!response.ok || data.error) {
        throw new Error(data.error?.message || "search_failed")
      }
      this.renderResults(data.items || [])
      this.setStatus(`${data.items?.length || 0}件の結果`, "ok")
    } catch (error) {
      this.setStatus("検索に失敗しました。APIキー設定を確認してください。", "error")
      this.resultsTarget.innerHTML = ""
    }
  }

  playFromResult(event) {
    const button = event.currentTarget
    const videoId = button.dataset.videoId
    if (!videoId) return
    this.playVideo(videoId)
    this.fetchDetails(videoId)
  }

  addToPlaylist(event) {
    const button = event.currentTarget
    const videoId = button.dataset.videoId
    if (!videoId) return
    if (this.playlistItems.some((item) => item.id === videoId)) return

    this.playlistItems.push({
      id: videoId,
      title: button.dataset.title || "Untitled",
      channel: button.dataset.channel || ""
    })
    this.renderPlaylist()
  }

  removeFromPlaylist(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (Number.isNaN(index)) return
    this.playlistItems.splice(index, 1)
    this.renderPlaylist()
  }

  playPlaylist() {
    if (!this.playerReady || this.playlistItems.length === 0) return
    const ids = this.playlistItems.map((item) => item.id)
    this.player.loadPlaylist(ids, 0)
    this.fetchDetails(ids[0])
  }

  playFromPlaylist(event) {
    const index = Number(event.currentTarget.dataset.index)
    if (!this.playerReady || Number.isNaN(index)) return
    const ids = this.playlistItems.map((item) => item.id)
    this.player.loadPlaylist(ids, index)
    const item = this.playlistItems[index]
    if (item) this.fetchDetails(item.id)
  }

  clearPlaylist() {
    this.playlistItems = []
    this.renderPlaylist()
  }

  play() {
    if (this.playerReady) this.player.playVideo()
  }

  pause() {
    if (this.playerReady) this.player.pauseVideo()
  }

  next() {
    if (this.playerReady) this.player.nextVideo()
  }

  prev() {
    if (this.playerReady) this.player.previousVideo()
  }

  async fetchDetails(videoId) {
    try {
      const response = await fetch(`/music/details?video_id=${encodeURIComponent(videoId)}`)
      const data = await response.json()
      if (!response.ok || data.error) {
        throw new Error(data.error?.message || "details_failed")
      }
      this.renderDetails(data)
    } catch (error) {
      this.setStatus("詳細情報の取得に失敗しました。", "error")
    }
  }

  async fetchExternal(video) {
    if (!this.hasExternalInfoTarget) return

    const title = video.title || ""
    const artist = video.channel_title || ""
    const query = `${title} ${artist}`.trim()
    if (!query) {
      this.externalInfoTarget.innerHTML = "<p class=\"detail-muted\">外部情報がありません</p>"
      return
    }

    this.externalInfoTarget.innerHTML = "<p class=\"detail-muted\">外部情報を取得中...</p>"
    try {
      const params = new URLSearchParams({
        q: query,
        title: title,
        artist: artist,
        video_id: video.id || "",
        channel_id: video.channel_id || ""
      })
      if (this.hasDebugValue && this.debugValue) {
        params.append("debug", "1")
      }
      const response = await fetch(`/music/external?${params}`)
      const data = await response.json()
      if (!response.ok || data.error) {
        throw new Error(data.error?.message || "external_failed")
      }
      this.renderExternal(data)
    } catch (error) {
      this.externalInfoTarget.innerHTML = "<p class=\"detail-muted\">外部情報を取得できませんでした</p>"
    }
  }

  renderResults(items) {
    if (items.length === 0) {
      this.resultsTarget.innerHTML = "<p class=\"empty\">検索結果がありません</p>"
      return
    }
    this.resultsTarget.innerHTML = items
      .map((item) => {
        const title = this.escapeHtml(item.title || "Untitled")
        const channel = this.escapeHtml(item.channel_title || "")
        const publishedAt = item.published_at ? this.formatDate(item.published_at) : ""
        const thumbnail = item.thumbnail || ""
        return `
          <div class="result-item">
            <img class="thumb" src="${thumbnail}" alt="">
            <div class="result-info">
              <p class="result-title">${title}</p>
              <p class="result-meta">${channel}${publishedAt ? ` • ${publishedAt}` : ""}</p>
            </div>
            <div class="result-actions">
              <button class="btn ghost" type="button" data-action="yt-music#playFromResult" data-video-id="${item.id}">Play</button>
              <button class="btn primary" type="button" data-action="yt-music#addToPlaylist" data-video-id="${item.id}" data-title="${this.escapeAttr(item.title)}" data-channel="${this.escapeAttr(item.channel_title)}">Add</button>
            </div>
          </div>
        `
      })
      .join("")
  }

  renderPlaylist() {
    if (this.playlistItems.length === 0) {
      this.playlistTarget.innerHTML = "<li class=\"empty\">まだ曲がありません</li>"
      return
    }
    this.playlistTarget.innerHTML = this.playlistItems
      .map((item, index) => {
        const title = this.escapeHtml(item.title)
        const channel = this.escapeHtml(item.channel)
        return `
          <li class="playlist-item">
            <button class="playlist-play" type="button" data-action="yt-music#playFromPlaylist" data-index="${index}">
              <span class="playlist-title">${title}</span>
              <span class="playlist-meta">${channel}</span>
            </button>
            <button class="btn ghost small" type="button" data-action="yt-music#removeFromPlaylist" data-index="${index}">Remove</button>
          </li>
        `
      })
      .join("")
  }

  renderDetails(data) {
    const video = data.video || {}
    const channel = data.channel || {}

    const title = this.escapeHtml(video.title || "Untitled")
    const channelTitle = this.escapeHtml(video.channel_title || "")
    const duration = video.duration ? this.formatDuration(video.duration) : ""
    const views = video.view_count ? this.formatNumber(video.view_count) : ""
    const likes = video.like_count ? this.formatNumber(video.like_count) : ""
    const published = video.published_at ? this.formatDate(video.published_at) : ""

    this.nowPlayingTarget.innerHTML = `
      <p class="now-title">${title}</p>
      <p class="now-meta">${channelTitle}${published ? ` • ${published}` : ""}</p>
    `

    this.trackInfoTarget.innerHTML = `
      <p class="detail-title">${title}</p>
      <p class="detail-meta">${channelTitle}</p>
      <div class="detail-stats">
        ${duration ? `<span>${duration}</span>` : ""}
        ${views ? `<span>${views} views</span>` : ""}
        ${likes ? `<span>${likes} likes</span>` : ""}
      </div>
      <p class="detail-desc">${this.escapeHtml(video.description || "").slice(0, 280)}${video.description?.length > 280 ? "..." : ""}</p>
    `

    const channelDesc = this.escapeHtml(channel.description || "")
    const channelViews = channel.view_count ? this.formatNumber(channel.view_count) : ""
    const channelSubs = channel.subscribers ? this.formatNumber(channel.subscribers) : ""

    this.channelInfoTarget.innerHTML = `
      <div class="channel-card">
        ${channel.thumbnail ? `<img class="channel-thumb" src="${channel.thumbnail}" alt="">` : ""}
        <div>
          <p class="detail-title">${this.escapeHtml(channel.title || channelTitle)}</p>
          <div class="detail-stats">
            ${channelSubs ? `<span>${channelSubs} subs</span>` : ""}
            ${channelViews ? `<span>${channelViews} views</span>` : ""}
          </div>
        </div>
      </div>
      <p class="detail-desc">${channelDesc.slice(0, 240)}${channelDesc.length > 240 ? "..." : ""}</p>
    `

    this.fetchExternal(video)
  }

  renderExternal(data) {
    const itunesItems = data.itunes?.items || []
    const top = itunesItems[0]

    const releaseDate = top?.release_date ? this.formatDate(top.release_date) : ""
    const trackTime = top?.track_time_ms ? this.formatMillis(top.track_time_ms) : ""
    const genre = top?.genre || ""
    const album = top?.album || ""

    const releaseHtml = top
      ? `
        <div class="itunes-card">
          ${top.artwork ? `<img class="itunes-art" src="${this.escapeAttr(top.artwork)}" alt="">` : ""}
          <div>
            <p class="detail-title">${this.escapeHtml(top.title || "Untitled")}</p>
            <p class="detail-meta">${this.escapeHtml(top.artist || "")}${album ? ` • ${this.escapeHtml(album)}` : ""}</p>
            <div class="detail-stats">
              ${releaseDate ? `<span>${releaseDate}</span>` : ""}
              ${genre ? `<span>${this.escapeHtml(genre)}</span>` : ""}
              ${trackTime ? `<span>${trackTime}</span>` : ""}
            </div>
            ${top.preview_url ? `<a class="mini-link" href="${this.escapeAttr(top.preview_url)}" target="_blank" rel="noopener">Preview</a>` : ""}
          </div>
        </div>
      `
      : "<p class=\"detail-muted\">リリース情報がありません</p>"

    const lyricsText = data.lyrics?.text ? this.truncateLines(data.lyrics.text, 12) : ""
    const lyricsHtml = lyricsText
      ? `
        <pre class="lyrics">${this.escapeHtml(lyricsText)}</pre>
        <p class="lyrics-source">source: ${this.escapeHtml(data.lyrics?.source || "lyrics")}</p>
      `
      : "<p class=\"detail-muted\">歌詞を取得できませんでした</p>"

    const links = Array.isArray(data.links) ? data.links : []
    const linksHtml = links.length
      ? `
        <div class="link-list">
          ${links
            .map((link) => `<a class="mini-link" href="${this.escapeAttr(link.url)}" target="_blank" rel="noopener">${this.escapeHtml(link.label)}</a>`)
            .join("")}
        </div>
      `
      : "<p class=\"detail-muted\">関連リンクがありません</p>"

    const debugHtml = data.debug
      ? `
        <details class="debug-panel">
          <summary>Debug</summary>
          <pre>${this.escapeHtml(JSON.stringify(data.debug, null, 2))}</pre>
        </details>
      `
      : ""

    this.externalInfoTarget.innerHTML = `
      <div class="external-section">
        <p class="detail-label">Release</p>
        ${releaseHtml}
      </div>
      <div class="external-section">
        <p class="detail-label">Lyrics</p>
        ${lyricsHtml}
      </div>
      <div class="external-section">
        <p class="detail-label">Links</p>
        ${linksHtml}
      </div>
      ${debugHtml}
    `
  }

  playVideo(videoId) {
    if (!this.playerReady) return
    this.player.loadVideoById(videoId)
  }

  loadYouTubeApi() {
    if (window.YT && window.YT.Player) {
      return Promise.resolve(window.YT)
    }
    if (window._ytApiPromise) return window._ytApiPromise

    window._ytApiPromise = new Promise((resolve) => {
      const tag = document.createElement("script")
      tag.src = "https://www.youtube.com/iframe_api"
      window.onYouTubeIframeAPIReady = () => resolve(window.YT)
      document.head.appendChild(tag)
    })
    return window._ytApiPromise
  }

  buildPlayer(YT) {
    if (this.player) return
    this.player = new YT.Player(this.playerTarget, {
      width: 360,
      height: 202,
      playerVars: {
        playsinline: 1,
        modestbranding: 1,
        rel: 0
      },
      events: {
        onReady: () => {
          this.playerReady = true
        },
        onAutoplayBlocked: () => {
          this.autoplayNoticeTarget.textContent = "自動再生がブロックされました。Playボタンを押してください。"
        }
      }
    })
  }

  setStatus(message, state) {
    if (!this.hasStatusTarget) return
    this.statusTarget.textContent = message
    this.statusTarget.dataset.state = state
  }

  formatDate(value) {
    const date = new Date(value)
    if (Number.isNaN(date.getTime())) return ""
    return date.toLocaleDateString("ja-JP", { year: "numeric", month: "short", day: "numeric" })
  }

  formatNumber(value) {
    return new Intl.NumberFormat("ja-JP").format(Number(value))
  }

  formatDuration(value) {
    const match = value.match(/PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?/)
    if (!match) return value
    const hours = Number(match[1] || 0)
    const minutes = Number(match[2] || 0)
    const seconds = Number(match[3] || 0)
    if (hours > 0) {
      return `${hours}:${String(minutes).padStart(2, "0")}:${String(seconds).padStart(2, "0")}`
    }
    return `${minutes}:${String(seconds).padStart(2, "0")}`
  }

  formatMillis(value) {
    const totalSeconds = Math.round(Number(value) / 1000)
    if (Number.isNaN(totalSeconds)) return ""
    const minutes = Math.floor(totalSeconds / 60)
    const seconds = totalSeconds % 60
    return `${minutes}:${String(seconds).padStart(2, "0")}`
  }

  truncateLines(value, maxLines) {
    const lines = String(value).split(/\r?\n/)
    if (lines.length <= maxLines) return value
    return `${lines.slice(0, maxLines).join("\n")}\n...`
  }

  escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;")
      .replace(/'/g, "&#39;")
  }

  escapeAttr(value) {
    return this.escapeHtml(value).replace(/`/g, "&#96;")
  }
}
