class SuperAdmin::LlmRouteProfilesController < SuperAdmin::ApplicationController
  before_action :set_profile, only: [:update, :destroy, :test_connection]

  def index
    ensure_default_profiles!
    @profiles = Llm::RouteProfile.global.order(:route_key)
  end

  def import_legacy
    ensure_default_profiles!
    key = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence
    model = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence
    Llm::RouteProfile.global.where.not(route_key: 'embedding').find_each do |profile|
      profile.update!(api_key: key, endpoint: endpoint.presence || profile.endpoint, model: model.presence || profile.model, enabled: true)
    end
    redirect_to super_admin_llm_route_profiles_path, notice: 'Legacy Captain configuration imported.'
  end

  def create
    profile = Llm::RouteProfile.global.find_or_initialize_by(route_key: params.require(:llm_route_profile).fetch(:route_key))
    profile.assign_attributes(profile_params)
    profile.embedding_dimensions = 1536 if profile.embedding?
    if profile.save
      redirect_to super_admin_llm_route_profiles_path, notice: 'LLM route profile saved.'
    else
      redirect_to super_admin_llm_route_profiles_path, alert: profile.errors.full_messages.to_sentence
    end
  end

  def update
    attrs = profile_params
    attrs = attrs.except(:api_key) if attrs[:api_key].blank?
    @profile.embedding_dimensions = 1536 if @profile.embedding?
    if @profile.update(attrs)
      redirect_to super_admin_llm_route_profiles_path, notice: 'LLM route profile saved.'
    else
      redirect_to super_admin_llm_route_profiles_path, alert: @profile.errors.full_messages.to_sentence
    end
  end

  def destroy
    @profile.destroy!
    redirect_to super_admin_llm_route_profiles_path, notice: 'LLM route profile removed.'
  end

  def test_connection
    attrs = profile_params
    attrs = attrs.except(:api_key) if attrs[:api_key].blank?
    @profile.assign_attributes(attrs)
    validate_test_profile!

    route = @profile.as_runtime_config(source: :test)
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    result = test_route(route)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round

    render json: { ok: true, model: @profile.model, dimensions: result[:dimensions], elapsed_ms: elapsed_ms }
  rescue StandardError => e
    render json: { ok: false, error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_default_profiles!
    Llm::RouteProfile::ROUTE_KEYS.each do |route_key|
      next if Llm::RouteProfile.global.exists?(route_key: route_key)

      model = if route_key == 'embedding'
                InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
              else
                Llm::Models.default_model_for(route_key)
              end
      Llm::RouteProfile.create!(route_key: route_key, provider: 'openai', protocol: 'openai_compatible', model: model,
                                endpoint: InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value.presence || 'https://api.openai.com/v1',
                                enabled: false)
    end
  end

  def set_profile
    @profile = Llm::RouteProfile.global.find(params[:id])
  end

  def validate_test_profile!
    raise Llm::RouteResolver::ConfigurationError, 'Model is required' if @profile.model.blank?
    raise Llm::RouteResolver::ConfigurationError, 'Endpoint is required' if @profile.endpoint.blank?
    raise Llm::RouteResolver::ConfigurationError, 'API key is required' if @profile.api_key.blank?
  end

  def test_route(route)
    Llm::Config.with_route(route) do |context|
      return test_embedding_route(context, route) if @profile.embedding?

      context.chat(
        model: route[:model], provider: route[:llm_provider] || route[:provider], assume_model_exists: true
      ).ask('Reply with OK')
      { dimensions: nil }
    end
  end

  def test_embedding_route(context, route)
    vectors = context.embed(
      'Chatwoot connection test', model: route[:model], provider: route[:llm_provider] || route[:provider], assume_model_exists: true
    ).vectors
    return { dimensions: vectors.length } if vectors.length == 1536

    raise Llm::RouteResolver::ConfigurationError, 'Configured embedding model must return 1536 dimensions'
  end

  def profile_params
    params.require(:llm_route_profile).permit(:route_key, :provider, :protocol, :model, :endpoint, :api_key, :enabled)
  end
end
