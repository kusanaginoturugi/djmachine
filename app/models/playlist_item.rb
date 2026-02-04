class PlaylistItem < ApplicationRecord
  belongs_to :playlist

  validates :video_id, presence: true, uniqueness: { scope: :playlist_id }
  validates :title, presence: true

  before_validation :normalize_fields

  private

  def normalize_fields
    self.video_id = video_id.to_s.strip
    self.title = title.to_s.strip
    self.channel_title = channel_title.to_s.strip
  end
end
