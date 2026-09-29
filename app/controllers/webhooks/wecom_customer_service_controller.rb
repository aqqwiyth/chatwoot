class Webhooks::WecomCustomerServiceController < ActionController::API
  def verify
    channel = Channel::WecomCustomerService.find_by!(identifier: params[:identifier])
    render plain: WecomCustomerService::CallbackService.new(channel: channel).verification_response(params), status: :ok
  rescue ActiveRecord::RecordNotFound
    head :not_found
  rescue ArgumentError
    head :unauthorized
  end

  def process_payload
    channel = Channel::WecomCustomerService.find_by!(identifier: params[:identifier])
    event = WecomCustomerService::CallbackService.new(channel: channel).callback_event(request)
    Webhooks::WecomCustomerServiceEventsJob.perform_later(
      channel_id: channel.id,
      token: event.fetch(:token),
      open_kfid: event.fetch(:open_kfid)
    )
    render plain: 'success', status: :ok
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'WeChat customer service channel not found' }, status: :not_found
  rescue ArgumentError => e
    render json: { error: e.message }, status: :unauthorized
  rescue StandardError => e
    Rails.logger.error("[WeComCustomerService] webhook processing failed: #{e.class}: #{e.message}")
    render json: { error: 'webhook processing failed' }, status: :bad_gateway
  end
end
