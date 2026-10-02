# == Schema Information
#
# Table name: captain_faq_suggestions
#
#  id                        :bigint           not null, primary key
#  answer                    :text             not null
#  embedding                 :vector(1536)
#  embedding_profile_version :integer          default(1), not null
#  language                  :string           default("en"), not null
#  question                  :string           not null
#  source_count              :integer          default(0), not null
#  status                    :integer          default("open"), not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  account_id                :bigint           not null
#  assistant_id              :bigint           not null
#
# Indexes
#
#  idx_cap_faq_suggestions_on_account_assistant_status_language  (account_id,assistant_id,status,language)
#  index_captain_faq_suggestions_on_account_id                   (account_id)
#  index_captain_faq_suggestions_on_assistant_id                 (assistant_id)
#  vector_idx_captain_faq_suggestions_embedding                  (embedding) USING ivfflat
#
class Captain::FaqSuggestion < ApplicationRecord
  self.table_name = 'captain_faq_suggestions'

  belongs_to :assistant, class_name: 'Captain::Assistant'
  belongs_to :account
  has_many :observations,
           class_name: 'Captain::FaqObservation',
           dependent: :delete_all,
           inverse_of: :faq_suggestion
  has_neighbors :embedding, normalize: true

  enum status: { open: 0, approved: 1, dismissed: 2 }

  validates :question, :answer, :language, presence: true

  before_validation :ensure_account
  before_validation :set_embedding_profile_version, if: -> { embedding.present? }
  after_commit :update_embedding, on: [:create, :update]

  scope :ordered, -> { order(source_count: :desc, updated_at: :desc) }
  scope :by_language, ->(language) { where(language: language) }

  private

  def set_embedding_profile_version
    self.embedding_profile_version ||= Llm::RouteResolver.embedding_profile_version(account_id)
  end

  def ensure_account
    self.account = assistant&.account
  end

  def update_embedding
    return unless open?
    return unless saved_change_to_question? || saved_change_to_answer? || embedding.nil?
    return if previously_new_record? && embedding.present?

    Captain::Llm::UpdateEmbeddingJob.perform_later(self, "#{question}: #{answer}")
  end
end
