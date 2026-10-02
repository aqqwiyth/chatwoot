# == Schema Information
#
# Table name: llm_route_profiles
#
#  id         :bigint           not null, primary key
#  api_key    :text
#  enabled    :boolean          default(TRUE), not null
#  endpoint   :string
#  model      :string           not null
#  options    :jsonb            not null
#  protocol   :string           default("openai_compatible"), not null
#  provider   :string           default("openai"), not null
#  route_key  :string           not null
#  version    :integer          default(1), not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  account_id :bigint
#
# Indexes
#
#  index_llm_route_profiles_on_account_id                (account_id)
#  index_llm_route_profiles_on_account_id_and_route_key  (account_id,route_key) UNIQUE
#  index_llm_route_profiles_on_route_key                 (route_key)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#
class Llm::RouteProfile < ApplicationRecord
  self.table_name = 'llm_route_profiles'

  belongs_to :account, optional: true

  ROUTE_KEYS = %w[
    editor assistant copilot label_suggestion conversation_completion document_faq_generation
    conversation_faq_generation conversation_faq_matching pdf_faq_generation help_center_article_generation
    onboarding_content_generation help_center_query_translation embedding
  ].freeze
  PROVIDERS = %w[openai aliyun custom].freeze
  PROTOCOLS = %w[openai_compatible].freeze

  encrypts :api_key if Chatwoot.encryption_configured?

  validates :route_key, inclusion: { in: ROUTE_KEYS }
  validates :provider, inclusion: { in: PROVIDERS }
  validates :protocol, inclusion: { in: PROTOCOLS }
  validates :model, presence: true, if: :enabled?
  validates :embedding_dimensions, numericality: { only_integer: true, equal_to: 1536 }, if: :embedding?

  scope :enabled, -> { where(enabled: true) }
  scope :global, -> { where(account_id: nil) }

  before_update :bump_version
  after_commit :enqueue_embedding_rebuild, on: :update

  def embedding?
    route_key == 'embedding'
  end

  def embedding_dimensions
    options['dimensions'] || 1536
  end

  def embedding_dimensions=(value)
    self.options = (options || {}).merge('dimensions' => value.to_i)
  end

  def masked_api_key
    return if api_key.blank?

    "#{api_key.first(4)}#{'*' * [api_key.length - 8, 4].max}#{api_key.last(4)}"
  end

  def as_runtime_config(source: nil)
    {
      route_key: route_key,
      provider: provider.to_sym,
      protocol: protocol.to_sym,
      llm_provider: protocol == 'openai_compatible' ? :openai : provider.to_sym,
      model: model,
      endpoint: endpoint,
      api_key: api_key,
      enabled: enabled,
      options: options || {},
      source: source,
      profile_version: version
    }
  end

  private

  def bump_version
    tracked = %w[provider protocol model endpoint api_key enabled options]
    self.version = version.to_i + 1 if tracked.any? { |attribute| will_save_change_to_attribute?(attribute) }
  end

  def enqueue_embedding_rebuild
    return unless embedding? && saved_change_to_version?

    return unless defined?(Captain::Llm::ReindexEmbeddingsJob)

    Captain::Llm::ReindexEmbeddingsJob.perform_later(account_id)
  end
end
