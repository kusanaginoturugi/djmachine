class Playlist < ApplicationRecord
  has_many :playlist_items, dependent: :destroy

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip
  end
end
