class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil)
    Llm::Config.initialize!
    @account_id = account_id
    @account = Account.find_by(id: account_id) if account_id
    @route = Llm::RouteResolver.resolve(route_key: 'embedding', account: @account)
    @embedding_model = @route&.dig(:model) || self.class.embedding_model
  end

  def self.embedding_model
    Llm::RouteResolver.resolve(route_key: 'embedding')&.dig(:model) ||
      InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    instrument_embedding_call(instrumentation_params(content, model)) do
      route = @route || {}
      vectors = Llm::Config.with_route(route) do |context|
        options = { model: model, provider: route[:llm_provider] || route[:provider], assume_model_exists: true }.compact
        context.embed(content, **options)
      end.vectors
      validate_dimensions!(vectors)
      vectors
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  def validate_dimensions!(vectors)
    return vectors if vectors.length == 1536

    raise EmbeddingsError, 'Configured embedding model must return 1536 dimensions'
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end
