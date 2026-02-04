class CreatePlaylistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_items do |t|
      t.references :playlist, null: false, foreign_key: true
      t.string :video_id, null: false
      t.string :title, null: false
      t.string :channel_title

      t.timestamps
    end

    add_index :playlist_items, %i[playlist_id video_id], unique: true
  end
end
