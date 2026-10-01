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
    route = @profile.as_runtime_config(source: :test)
    result = Llm::Config.with_route(route) do |context|
      if @profile.embedding?
        vectors = context.embed('Chatwoot connection test', model: route[:model], provider: route[:llm_provider] || route[:provider], assume_model_exists: true).vectors
        raise Llm::RouteProfile::ConfigurationError, 'Configured embedding model must return 1536 dimensions' unless vectors.length == 1536
      else
        context.chat(model: route[:model], provider: route[:llm_provider] || route[:provider], assume_model_exists: true).ask('Reply with OK')
      end
    end
    render json: { ok: true, model: @profile.model, dimensions: result.respond_to?(:vectors) ? result.vectors.length : nil }
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

  def profile_params
    params.require(:llm_route_profile).permit(:route_key, :provider, :protocol, :model, :endpoint, :api_key, :enabled)
  end
end
