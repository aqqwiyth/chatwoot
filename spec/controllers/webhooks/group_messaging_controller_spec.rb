require 'rails_helper'

RSpec.describe 'Group messaging webhooks', type: :request do
  let(:channel) do
    create(
      :channel_group_messaging,
      provider: 'wecom',
      provider_config: {
        'company_name' => '测试企业',
        'company_id' => 'test-company',
        'allowed_group_owners' => [],
        'allowed_group_ids' => [],
        'ignored_group_ids' => []
      }
    )
  end
  let(:payload) { JSON.parse(file_fixture('group_messaging/wecom_text_event.json').read) }

  it 'accepts an official WeCom text callback' do
    post "/webhooks/group_messaging/wecom/#{channel.identifier}", params: payload, as: :json

    expect(response).to have_http_status(:ok)
    expect(channel.inbox.messages.last.extensions.dig('actor', 'display_name')).to eq('麦季')
    expect(channel.inbox.messages.last.content).to eq('筛选其他erp发货的订单是吗')
  end
end
