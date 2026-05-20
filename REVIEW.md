# djmachine コードレビュー

レビュー日: 2026-04-05

---

## プロジェクト概要

YouTube 動画再生に iTunes / lyrics.ovh / LibreTranslate / Wikipedia などの外部情報を組み合わせた音楽プレイヤー Web アプリ。

| 項目 | 内容 |
|------|------|
| フレームワーク | Ruby on Rails 8.1.1 |
| Ruby | 3.4.7 |
| DB | SQLite3 |
| フロントエンド | Stimulus.js + Turbo + Importmap |
| デプロイ | Docker + Kamal |

---

## 総合評価: 7/10

**良い点:** Rails らしいクリーンな設計、優れたフロントエンド実装、DevOps 整備済み  
**主な課題:** テストゼロ、CSP 無効、レート制限なし

---

## 強み

### 1. アーキテクチャ
- サービスクラスで外部 API を適切に分離（`YoutubeClient`, `ExternalInfoClient`, `LibreTranslateClient`）
- 薄いコントローラー、MVC の責務分離が明確

### 2. フロントエンド
- Stimulus コントローラー (`yt_music_controller.js`, 651行) がよく整理されている
- `escapeHtml()` / `escapeAttr()` による XSS 対策を実装済み
- CSRF トークンの適切な処理

### 3. データ整合性
- `(playlist_id, video_id)` のユニーク複合インデックス
- `ON DELETE CASCADE` による外部キー制約
- プレイリスト名の大文字小文字を区別しないユニーク制約

### 4. セキュリティの基礎
- API キーは環境変数から取得
- Rails ORM による SQL インジェクション防止
- CSRF 保護有効

### 5. 開発環境
- Rubocop, Brakeman, bundler-audit 導入済み
- Docker + Kamal で本番デプロイ対応
- GitHub Actions CI/CD 設定済み

---

## 問題点と改善提案

### 優先度: 高

#### 1. テストが存在しない
- `test/` 配下にコントローラー・モデル・サービスのテストが一切ない
- **影響:** リグレッション検知不可、リファクタリングが困難
- **対策:** 最低限、モデルのバリデーションとサービスクラスのユニットテストを追加する

#### 2. Content Security Policy が無効
- `config/initializers/content_security_policy.rb` が全てコメントアウト
- **リスク:** HTML エスケープはされているが、XSS 攻撃の防御層が薄い
- **対策:** YouTube iframe / 外部 API ドメインを許可した CSP を有効化する

```ruby
# 例
policy.default_src :self
policy.frame_src "https://www.youtube.com"
policy.connect_src :self, "https://itunes.apple.com", "https://api.lyrics.ovh"
```

#### 3. レート制限がない
- 外部 API へのリクエストに制限なし
- **リスク:** API クォータ超過、DDoS 被害
- **対策:** `rack-attack` などのミドルウェアを導入する

#### 4. 入力値の長さ検証がない
- `params[:text].to_s` などで外部 API に無制限の文字列を渡せる
- **リスク:** リソース枯渇、翻訳 API のコスト増大
- **対策:** 各 params に最大長チェックを追加する（例: `text.truncate(5000)`）

#### 5. デバッグパラメーターの情報漏洩リスク
- `params[:debug] == "1"` で本番環境でも詳細エラー情報を返せる状態
- **対策:** `Rails.env.development?` のみに限定し、`params[:debug]` サポートを削除する

---

### 優先度: 中

#### 6. 歌詞マッチングロジックが複雑・脆弱
- `build_lyrics_candidates()` の複数デリミタ正規表現は誤マッチしやすい
- `music_controller.rb:343-376`
```ruby
match = text.match(/(.+?)\s*(?:-+|–|—|\||｜|\/|:)\s*(.+)/)
```
- **対策:** ファジーマッチングライブラリの導入、またはユニットテストで網羅的に検証する

#### 7. 外部 API 呼び出しが同期処理
- YouTube 検索 → iTunes → 歌詞取得を全て同期的に処理
- **影響:** ユーザーが全 API の完了を待つ必要がある
- **対策:** 二次情報（iTunes, 歌詞）はバックグラウンドジョブや非同期 fetch に切り出す

#### 8. API レスポンスのキャッシュなし
- 同じクエリを毎回外部 API に送信
- **対策:** Rails.cache を使い、同一クエリ結果を数時間キャッシュする

#### 9. HTTP タイムアウトが固定値
- `open_timeout = 3`, `read_timeout = 6` がハードコード
- **対策:** 環境変数か設定ファイルで変更可能にする

#### 10. データベーストランザクション未使用
- `add_to_playlist()` などでトランザクションを使用していない
- **リスク:** 競合状態での部分的な更新
- **対策:** `ActiveRecord::Base.transaction` で囲む

---

### 優先度: 低

#### 11. 検索結果にページネーションなし
- YouTube 12件、iTunes 5件に固定
- **対策:** offset/page パラメーターを追加して追加読み込みに対応する

#### 12. LibreTranslate チャンク結合の改行問題
- `translated_chunks.join("\n")` で元の改行構造が変わる可能性がある
- `libre_translate_client.rb:27`

#### 13. iTunes URL がハードコード
- `ExternalInfoClient` の定数として埋め込まれている
- LibreTranslate は ENV 対応済みなので一貫性のためこちらも対応推奨

---

## ファイル別評価

| ファイル | 行数 | 評価 | コメント |
|---------|------|------|---------|
| `music_controller.rb` | 431 | 良 | 歌詞ロジックが複雑、分割推奨 |
| `yt_music_controller.js` | 651 | 優 | よく整理されている |
| `youtube_client.rb` | 53 | 良 | シンプルで明瞭 |
| `external_info_client.rb` | 48 | 良 | シンプルで明瞭 |
| `libre_translate_client.rb` | 84 | 良 | チャンク処理が工夫されている |
| `app.css` | 557 | 優 | レスポンシブデザイン、整理されている |
| `playlist.rb` | 13 | 良 | 適切なバリデーション |
| `playlist_item.rb` | 16 | 良 | 適切なバリデーション |

---

## DB スキーマ

```
playlists        : id, name (unique/case-insensitive), timestamps
playlist_items   : id, playlist_id (FK cascade), video_id, title, channel_title, timestamps
                   UNIQUE (playlist_id, video_id)
```

現在の用途には適切。将来的にユーザー認証や検索履歴を追加する場合は拡張が必要。

---

## まとめ

個人利用・プロトタイプとして完成度は高い。本番公開・複数ユーザーでの利用を想定する場合は以下が必須:

1. テストの追加（最優先）
2. CSP の有効化
3. レート制限の導入
4. デバッグパラメーターの削除
5. 入力値バリデーションの強化
