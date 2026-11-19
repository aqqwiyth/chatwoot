class WecomCustomerService::IsvCredentialService
  def initialize(corp_id:)
    @corp_id = corp_id
  end

  def access_token
    base_url = ENV.fetch('WECOM_ISV_CREDENTIAL_URL').delete_suffix('/')
    api_key = ENV.fetch('WECOM_ISV_CREDENTIAL_KEY')
    response = HTTParty.post(
      "#{base_url}/internal/corp-token",
      headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" },
      body: { corp_id: @corp_id }.to_json,
      timeout: 10,
      follow_redirects: false
    )
    raise 'ISV credential service request failed' unless response.success?

    payload = response.parsed_response
    raise 'ISV credential service returned invalid token' unless payload.is_a?(Hash) && payload['access_token'].present?

    payload['access_token']
  end
end
