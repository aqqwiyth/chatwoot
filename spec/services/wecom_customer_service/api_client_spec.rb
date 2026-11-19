require 'rails_helper'

RSpec.describe WecomCustomerService::ApiClient do
  let(:channel) do
    instance_double(
      Channel::WecomCustomerService,
      id: 123,
      corp_id: 'corp-id',
      secret: 'secret',
      credential_mode: 'direct',
      open_kfid: 'open-kfid'
    )
  end
  let(:client) { described_class.new(channel: channel) }
  let(:response) { double('response', success?: true, code: 200, parsed_response: { 'errcode' => 0 }) }

  before do
    allow(Rails.cache).to receive(:fetch).and_return('access-token')
  end

  describe 'ISV credentials' do
    it 'requests the authorized corporation token from the internal credential service' do
      allow(channel).to receive(:credential_mode).and_return('isv')
      token_response = instance_double(HTTParty::Response, success?: true, parsed_response: { 'access_token' => 'isv-token' })
      with_modified_env WECOM_ISV_CREDENTIAL_URL: 'http://credential-service:8000', WECOM_ISV_CREDENTIAL_KEY: 'internal-key' do
        expect(HTTParty).to receive(:post).with(
          'http://credential-service:8000/internal/corp-token',
          headers: { 'Content-Type' => 'application/json', 'Authorization' => 'Bearer internal-key' },
          body: { corp_id: 'corp-id' }.to_json,
          timeout: 10,
          follow_redirects: false
        ).and_return(token_response)
        expect(client.send(:access_token)).to eq('isv-token')
      end
    end
  end

  describe '#send_event_response' do
    it 'sends a text response using the event code' do
      expect(HTTParty).to receive(:post).with(
        'https://qyapi.weixin.qq.com/cgi-bin/kf/send_msg_on_event',
        query: { access_token: 'access-token' },
        headers: { 'Content-Type' => 'application/json' },
        body: anything,
        timeout: 10
      ) do |_url, options|
        expect(JSON.parse(options[:body])).to eq(
          'code' => 'welcome-code',
          'msgid' => 'response-id',
          'msgtype' => 'text',
          'text' => { 'content' => 'Welcome' }
        )
        response
      end

      client.send_event_response(code: 'welcome-code', content: 'Welcome', msgid: 'response-id')
    end
  end
end
