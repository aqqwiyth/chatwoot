module GroupMessaging
  class EventNormalizer
    REQUIRED_ACTOR_KEYS = %w[external_id display_name].freeze

    def self.normalize(payload, provider:)
      data = payload.to_h.deep_stringify_keys
      data = normalize_wecom_payload(data) if provider == 'wecom'
      actor_data = data['actor'].is_a?(Hash) ? data['actor'] : {}
      actor = actor_data.slice(*REQUIRED_ACTOR_KEYS, 'identity_key', 'avatar_url', 'role', 'is_bot')
      missing_actor_keys = REQUIRED_ACTOR_KEYS.reject { |key| actor[key].present? }
      raise ArgumentError, "actor requires #{missing_actor_keys.join(', ')}" if missing_actor_keys.any?
      actor['identity_key'] ||= "#{provider}:#{actor['external_id']}" if actor['external_id'].present?

      event = {
        provider: provider,
        external_event_id: data['external_event_id'] || data.dig('provider', 'event_id'),
        external_message_id: data['external_message_id'] || data.dig('provider', 'message_id'),
        group_id: data['group_id'] || data.dig('group', 'external_id'),
        group: data['group'].is_a?(Hash) ? data['group'] : {},
        actor: actor,
        content: data['content'],
        content_type: data['content_type'] || 'text',
        kind: data['kind'] || 'text',
        action: data['action'],
        recalled_message_id: data['recalled_message_id'] || data.dig('revoke', 'pre_msgid'),
        extensions: data['extensions'].is_a?(Hash) ? data['extensions'].deep_stringify_keys : {},
        provider_data: data['provider'].is_a?(Hash) ? data['provider'] : {}
      }
      raise ArgumentError, 'external_event_id is required' if event[:external_event_id].blank?

      event
    end

    def self.normalize_wecom_payload(data)
      text = data['text'].is_a?(Hash) ? data['text'] : {}
      group = data['group'].is_a?(Hash) ? data['group'].deep_stringify_keys : {}
      actor = data['actor'].is_a?(Hash) ? data['actor'].deep_stringify_keys : {}
      group['display_name'] ||= data['groupName']
      group['owner_id'] ||= data['owner']
      group['member_ids'] ||= data['tolist'] if data['tolist'].is_a?(Array)
      actor['external_id'] ||= data['from']
      actor['display_name'] ||= data['actorName'] || data['from']
      actor['identity_key'] ||= "wecom:#{actor['external_id']}" if actor['external_id'].present?

      data.merge(
        'external_event_id' => data['msgid'] || data['external_event_id'],
        'external_message_id' => data['msgid'] || data['external_message_id'],
        'group_id' => data['roomid'] || data['group_id'],
        'group' => group,
        'actor' => actor,
        'content' => text['content'] || data['content'],
        'content_type' => data['msgtype'] || data['content_type'],
        'kind' => data['action'] || data['kind'],
        'provider' => data.slice('owner', 'groupName', 'tolist', 'msgtime', 'msgid', 'action', 'from', 'actorName', 'msgtype', 'time', 'roomid', 'revoke')
      )
    end
  end
end
