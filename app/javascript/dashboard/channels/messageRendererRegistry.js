const registrations = [];

export function registerChannelExtension(extension) {
  if (!extension || !extension.channel) {
    throw new Error('channel extension requires a channel');
  }
  registrations.push({ ...extension, messageKind: extension.messageKind || '*' });
}

export function resolveChannelExtension({ channel, provider, messageKind }) {
  const candidates = registrations.filter(item => {
    const channelMatch = item.channel === channel || item.channel === '*';
    const providerMatch = !item.provider || item.provider === provider || item.provider === '*';
    const kindMatch = item.messageKind === '*' || item.messageKind === messageKind;
    return channelMatch && providerMatch && kindMatch;
  });

  return candidates.sort((a, b) => {
    const score = item =>
      (item.channel === channel ? 4 : 0) +
      (item.provider === provider ? 2 : 0) +
      (item.messageKind === messageKind ? 1 : 0);
    return score(b) - score(a);
  })[0] || null;
}

export default { registerChannelExtension, resolveChannelExtension };
