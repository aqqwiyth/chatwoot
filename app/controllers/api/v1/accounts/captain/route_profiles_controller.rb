class Api::V1::Accounts::Captain::RouteProfilesController < Api::V1::Accounts::BaseController
  before_action :authorize_account_update

  def index
    render json: { routes: @current_account.llm_route_profiles.order(:route_key).map { |profile| serialize(profile) } }
  end

  def create
    profile = @current_account.llm_route_profiles.find_or_initialize_by(route_key: params.require(:route_key))
    profile.assign_attributes(route_profile_params)
    profile.embedding_dimensions = 1536 if profile.embedding?
    profile.save!
    render json: serialize(profile), status: :created
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    @current_account.llm_route_profiles.find_by!(route_key: params.require(:route_key)).destroy!
    head :no_content
  end

  private

  def authorize_account_update
    authorize @current_account, :update?
  end

  def route_profile_params
    permitted = params.permit(:provider, :protocol, :model, :endpoint, :api_key, :enabled)
    permitted.delete(:api_key) if permitted[:api_key].blank?
    permitted
  end

  def serialize(profile)
    profile.as_runtime_config(source: :account_profile).except(:api_key).merge(api_key: profile.masked_api_key,
                                                                                 dimensions: profile.embedding? ? 1536 : nil)
  end
end
