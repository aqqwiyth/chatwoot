class Api::V1::Accounts::WecomReceptionController < Api::V1::Accounts::BaseController
  before_action :fetch_inbox
  rescue_from WecomCustomerService::ApiError, with: :render_wecom_error

  def show
    render json: { departments: client.list_departments.fetch('department'), servicers: client.list_servicers.fetch('servicer_list'),
                   servicer_names: @inbox.channel.reception_servicer_names }
  end

  def members
    render json: { members: client.list_department_members(department_id: params.require(:department_id)).fetch('userlist') }
  end

  def update
    selected = params.fetch(:servicer_userids)
    raise ActionController::BadRequest unless selected.is_a?(Array) && selected.all? { |id| id.is_a?(String) && id.present? }

    names = params.fetch(:servicer_names, ActionController::Parameters.new).permit(*selected).to_h
    service = WecomCustomerService::ServicerSyncService.new(channel: @inbox.channel, client: client, userids: selected, names: names)
    render json: { servicers: service.perform }
  end

  private

  def fetch_inbox
    @inbox = Current.account.inboxes.find(params[:id])
    authorize @inbox, :show?
    authorize @inbox, :update?
    head :not_found unless @inbox.wecom_customer_service?
  end

  def client
    @client ||= WecomCustomerService::ApiClient.new(channel: @inbox.channel)
  end

  def render_wecom_error(error)
    render json: { message: error.message }, status: :unprocessable_entity
  end
end
