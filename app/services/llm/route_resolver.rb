module Llm
  class RouteResolver
    class ConfigurationError < StandardError; end

    FEATURE_TO_ROUTE = {
      'reply_suggestion' => 'editor', 'summarize' => 'editor', 'rewrite' => 'editor',
      'tone_rewrite' => 'editor', 'editor' => 'editor', 'label_suggestion' => 'label_suggestion'
    }.freeze

    class << self
      def route_keys
        Llm::RouteProfile::ROUTE_KEYS
      end

      def resolve(route_key:, account: nil)
        key = route_key.to_s
        account_profile = account && Llm::RouteProfile.enabled.find_by(account_id: account.id, route_key: key)
        global_profile = Llm::RouteProfile.enabled.global.find_by(route_key: key)
        if account_profile
          base = global_profile&.as_runtime_config(source: :global_profile) || legacy_profile(key, account)
          overrides = account_profile.as_runtime_config(source: :account_profile)
          return (base || {}).merge(overrides.compact).merge(source: :account_profile, route_key: key)
        end
        return global_profile.as_runtime_config(source: :global_profile) if global_profile

        legacy_profile(key, account)
      end

      def route_for_feature(feature, account: nil)
        resolve(route_key: FEATURE_TO_ROUTE.fetch(feature.to_s, feature.to_s), account: account)
      end

      def embedding_profile_version(account_id)
        account = Account.find_by(id: account_id)
        (resolve(route_key: 'embedding', account: account)&.fetch(:profile_version, 1) || 1).to_i
      end

      private

      def legacy_profile(route_key, account)
        account_model_candidate = account&.captain_models&.[](route_key).presence
        account_model = account_model_candidate if account_model_candidate && Llm::Models.valid_model_for?(route_key, account_model_candidate)
        installation_model = if route_key == 'embedding'
                               InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence
                             elsif route_key == 'conversation_completion' && ChatwootApp.self_hosted_enterprise?
                               InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
                             end
        model = account_model || installation_model
        endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence
        key = legacy_key(route_key, account)
        return nil if model.blank? && key.blank? && endpoint.blank?

        {
          route_key: route_key, provider: :openai, llm_provider: :openai, protocol: :openai_compatible,
          model: model || Llm::Models.default_model_for(route_key), endpoint: legacy_endpoint(endpoint),
          api_key: key || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence,
          enabled: true, options: {}, source: model.present? && account_model.present? ? :account_override : :legacy, profile_version: 1
        }
      end

      def legacy_key(route_key, account)
        if route_key == 'editor' && account
          account.hooks.find_by(app_id: 'openai', status: 'enabled')&.settings&.dig('api_key').presence
        end || InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
      end

      def legacy_endpoint(endpoint)
        value = (endpoint.presence || 'https://api.openai.com').chomp('/')
        value.end_with?('/v1') || value.include?('/compatible-mode/') ? value : "#{value}/v1"
      end
    end
  end
end
