class Llm::PromptTemplate < ApplicationRecord
  self.table_name = 'llm_prompt_templates'

  belongs_to :updated_by, class_name: 'SuperAdmin', optional: true

  validates :key, :content, presence: true
  validates :content, length: { maximum: 100_000 }
  validates :key, uniqueness: true

  before_validation :set_checksum
  before_update :increment_revision

  def metadata
    super || {}
  end

  private

  def set_checksum
    self.source_checksum = Digest::SHA256.hexdigest(content.to_s)
  end

  def increment_revision
    self.revision = revision.to_i + 1 if will_save_change_to_content?
  end
end
