module Llm::FeatureRouter
  class UnknownFeatureError < StandardError; end

  CAPTAIN_V2_ASSISTANT_MODEL = 'gpt-5.2'.freeze

  class << self
    def resolve(feature:, account: nil)
      feature_key = feature.to_s
      raise UnknownFeatureError, "Unknown LLM feature: #{feature_key}" unless Llm::Models.feature?(feature_key)

      configured_route = Llm::RouteResolver.route_for_feature(feature_key, account: account)
      return configured_route.merge(feature: feature_key) if configured_route

      model, source = model_and_source(account, feature_key)

      {
        feature: feature_key,
        provider: provider_for(model, source),
        model: model,
        source: source,
        route_key: feature_key,
        protocol: :openai_compatible,
        endpoint: normalized_endpoint,
        profile_version: 1
      }
    end

    private

    def model_and_source(account, feature_key)
      account_model = account_model_override(account, feature_key)
      return [account_model, :account_override] if account_model.present?

      installation_model = installation_model_override(feature_key)
      return [installation_model, :installation_override] if installation_model.present?

      [captain_v2_assistant_model(account, feature_key) || Llm::Models.default_model_for(feature_key), :default]
    end

    def account_model_override(account, feature_key)
      model = account&.captain_models&.[](feature_key).presence
      return unless model
      return model if Llm::Models.valid_model_for?(feature_key, model)
    end

    def installation_model_override(feature_key)
      return unless feature_key == 'conversation_completion'
      return unless ChatwootApp.self_hosted_enterprise?

      InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
    end

    def provider_for(model, source)
      Llm::Models.provider_for(model) || ('openai' if source == :installation_override)
    end

    def captain_v2_assistant_model(account, feature_key)
      return unless feature_key == 'assistant'
      return unless account&.feature_enabled?('captain_integration_v2')

      CAPTAIN_V2_ASSISTANT_MODEL
    end

    def normalized_endpoint
      endpoint = (InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com').chomp('/')
      endpoint.end_with?('/v1') || endpoint.include?('/compatible-mode/') ? endpoint : "#{endpoint}/v1"
    end
  end
end
