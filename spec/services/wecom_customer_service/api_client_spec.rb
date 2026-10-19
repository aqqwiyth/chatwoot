require 'rails_helper'

RSpec.describe WecomCustomerService::ApiClient do
  let(:channel) do
    instance_double(
      Channel::WecomCustomerService,
      id: 123,
      corp_id: 'corp-id',
      secret: 'secret',
      open_kfid: 'open-kfid'
    )
  end
  let(:client) { described_class.new(channel: channel) }
  let(:response) { double('response', success?: true, code: 200, parsed_response: { 'errcode' => 0 }) }

  before do
    allow(Rails.cache).to receive(:fetch).and_return('access-token')
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
