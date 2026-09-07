require 'rails_helper'

RSpec.describe GroupMessaging::InboundMessageService do
  let(:channel) { create(:channel_group_messaging) }
  let(:inbox) { channel.inbox }
  let(:event) do
    {
      provider: 'feishu',
      external_event_id: 'event-1',
      external_message_id: 'message-1',
      group_id: 'group-1',
      group: { 'display_name' => '研发一群' },
      actor: {
        'identity_key' => 'feishu:member-1',
        'external_id' => 'member-1',
        'display_name' => '张三',
        'avatar_url' => 'https://example.test/avatar.png'
      },
      content: 'hello',
      content_type: 'text',
      kind: 'text',
      extensions: {},
      provider_data: { 'event_id' => 'event-1' }
    }
  end

  it 'creates one group conversation and stores the actor snapshot' do
    message = described_class.new(inbox: inbox, event: event).perform

    expect(message.conversation.contact.contact_type).to eq('group')
    expect(message.conversation.contact.name).to eq('研发一群')
    expect(message.extensions.dig('actor', 'display_name')).to eq('张三')
    expect(inbox.conversations.count).to eq(1)
  end

  it 'is idempotent for repeated external events' do
    service = described_class.new(inbox: inbox, event: event)
    first = service.perform
    second = service.perform

    expect(second.id).to eq(first.id)
    expect(inbox.messages.where(external_event_id: 'event-1').count).to eq(1)
  end
end
