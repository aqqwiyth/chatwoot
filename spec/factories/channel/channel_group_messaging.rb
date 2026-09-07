FactoryBot.define do
  factory :channel_group_messaging, class: 'Channel::GroupMessaging' do
    account
    sequence(:identifier) { |n| "group-channel-#{n}" }
    provider { 'feishu' }
    provider_config do
      {
        'webhook_secret' => 'test-secret',
        'send_url' => 'https://example.test/messages',
        'access_token' => 'test-token'
      }
    end
    capabilities { { 'mentions' => true, 'threads' => true } }

    after(:create) do |channel|
      create(:inbox, channel: channel, account: channel.account, lock_to_single_conversation: true)
    end
  end
end
