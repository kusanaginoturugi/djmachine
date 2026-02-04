# djmachine

音楽を再生しながら、楽曲やミュージシャンの情報も同時に表示する実験的なRailsアプリです。

## 主な機能
- YouTube 再生（小さめプレーヤー）
- 検索結果から再生・プレイリスト追加
- プレイリストのDB保存（未指定は "Watch Later"）
- 外部情報（iTunes / lyrics.ovh / 関連リンク）
- 歌詞の翻訳（LibreTranslate）

## 必要要件
- Ruby（`.ruby-version` 参照）
- Node は不要（Importmap）
- DB（開発はSQLite想定）

## セットアップ
```bash
bundle install
bin/rails db:migrate
```

## 環境変数
```
YOUTUBE_API_KEY=xxxxxxxxxxxxxxxx
# 任意（未設定時は http://localhost:65000）
LIBRETRANSLATE_URL=http://localhost:65000
```

## 起動
```bash
bin/dev
# もしくは
bin/rails s
```

## 使い方
1. `/music` にアクセス
2. 検索 → Play で再生
3. Add でプレイリストに保存
4. 翻訳ボタンで歌詞を翻訳（LibreTranslate が起動している場合）

## 外部サービス
- YouTube Data API v3（検索/詳細取得に使用）
- iTunes Search API（リリース情報）
- lyrics.ovh（歌詞）
- LibreTranslate（翻訳）

## メモ
- 初回再生はユーザー操作が必要です
- 開発環境では外部情報のデバッグ情報を表示します
