class Webhooks::GroupMessagingController < ActionController::API
  def process_payload
    channel = Channel::GroupMessaging.find_by!(provider: params[:provider], identifier: params[:identifier])
    channel.adapter.verify!(request)
    event = channel.adapter.normalize_event(request.request_parameters)
    message = GroupMessaging::InboundMessageService.new(inbox: channel.inbox, event: event).perform
    render json: (message ? message.push_event_data : { status: 'ignored' }), status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Group messaging channel not found' }, status: :not_found
  rescue ArgumentError => e
    status = e.message == 'invalid webhook signature' ? :unauthorized : :unprocessable_entity
    render json: { error: e.message }, status: status
  end
end
