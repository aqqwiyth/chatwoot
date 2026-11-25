class Api::V1::Accounts::WecomEndConfigsController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox

  rescue_from ActiveRecord::RecordInvalid, with: :render_validation_error

  def update
    channel = @inbox.channel
    ActiveRecord::Base.transaction do
      end_config_params.each do |config|
        channel.end_configs.find_or_initialize_by(scope: config[:scope]).update!(config.except(:scope).to_h)
      end
    end

    render json: { end_configs: channel.end_configs_snapshot.map(&:api_payload) }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :update?
    head :not_found unless @inbox.wecom_customer_service?
  end

  def end_config_params
    rows = params.require(:end_configs)
    raise ActionController::BadRequest unless rows.is_a?(Array)

    configs = rows.map { |row| row.permit(:scope, :auto_close_after_minutes, :satisfaction_enabled, :satisfaction_message, :ending_message) }
    scopes = configs.map { |config| config[:scope].to_s }
    raise ActionController::BadRequest unless scopes.sort == WecomCustomerService::EndConfig::SCOPES.sort

    configs
  end

  def render_validation_error(error)
    render json: { message: error.record.errors.full_messages.join(', ') }, status: :unprocessable_entity
  end
end
