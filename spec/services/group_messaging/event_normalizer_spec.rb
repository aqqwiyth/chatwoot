require 'rails_helper'

RSpec.describe GroupMessaging::EventNormalizer do
  let(:payload) do
    {
      group_id: 'group-1',
      external_event_id: 'event-1',
      external_message_id: 'message-1',
      content: 'hello',
      actor: { display_name: 'Alice', external_id: 'user-1' }
    }
  end

  it 'normalizes actor identity and provider metadata' do
    event = described_class.normalize(payload, provider: 'feishu')

    expect(event[:actor]['identity_key']).to eq('feishu:user-1')
    expect(event[:provider]).to eq('feishu')
    expect(event[:external_event_id]).to eq('event-1')
  end

  it 'rejects events without an idempotency key' do
    expect {
      described_class.normalize(payload.except(:external_event_id), provider: 'feishu')
    }.to raise_error(ArgumentError, /external_event_id/)
  end

  it 'rejects events without an actor identity' do
    expect {
      described_class.normalize(payload.merge(actor: {}), provider: 'feishu')
    }.to raise_error(ArgumentError, /actor requires/)
  end

  it 'normalizes the official WeCom callback shape' do
    event = described_class.normalize(
      {
        owner: 'jiangting',
        groupName: '实施群',
        tolist: ['jiangting', 'member-1'],
        msgtime: 1_784_708_380_950,
        msgid: 'wecom-message-1',
        action: 'send',
        from: 'guokui.jhh',
        actorName: '麦季',
        msgtype: 'text',
        text: { content: 'hello' },
        roomid: 'room-1'
      },
      provider: 'wecom'
    )

    expect(event[:external_event_id]).to eq('wecom-message-1')
    expect(event[:group_id]).to eq('room-1')
    expect(event.dig(:group, 'display_name')).to eq('实施群')
    expect(event.dig(:group, 'owner_id')).to eq('jiangting')
    expect(event.dig(:group, 'member_ids')).to eq(['jiangting', 'member-1'])
    expect(event.dig(:actor, 'external_id')).to eq('guokui.jhh')
    expect(event.dig(:actor, 'display_name')).to eq('麦季')
    expect(event[:content]).to eq('hello')
  end

  it 'extracts the original message id from a WeCom recall event' do
    event = described_class.normalize(
      { msgid: 'recall-1', action: 'recall', from: 'kenshin', msgtype: 'revoke', revoke: { pre_msgid: 'original-1' } },
      provider: 'wecom'
    )

    expect(event[:recalled_message_id]).to eq('original-1')
  end
end
