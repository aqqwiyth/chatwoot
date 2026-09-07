import {
  registerChannelExtension,
  resolveChannelExtension,
} from './messageRendererRegistry';

describe('messageRendererRegistry', () => {
  it('prefers provider and message kind matches', () => {
    const generic = { channel: 'Channel::GroupMessaging', messageKind: '*' };
    const specific = {
      channel: 'Channel::GroupMessaging',
      provider: 'feishu',
      messageKind: 'text',
    };
    registerChannelExtension(generic);
    registerChannelExtension(specific);

    expect(
      resolveChannelExtension({
        channel: 'Channel::GroupMessaging',
        provider: 'feishu',
        messageKind: 'text',
      })
    ).toEqual(specific);
  });

  it('returns null when no extension matches', () => {
    expect(
      resolveChannelExtension({
        channel: 'Channel::Email',
        provider: null,
        messageKind: 'text',
      })
    ).toBeNull();
  });
});
