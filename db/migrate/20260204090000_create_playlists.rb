class CreatePlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :playlists do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :playlists, :name, unique: true
  end
end
