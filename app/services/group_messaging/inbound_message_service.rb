module GroupMessaging
  class InboundMessageService
    def initialize(inbox:, event:)
      @inbox = inbox
      @event = event
    end

    def perform
      return mark_recalled_message if @event[:recalled_message_id].present?
      return existing_message if existing_message
      return if @event[:action].present? && @event[:action] != 'send'
      return if filtered_event?

      contact_inbox = GroupResolver.new(inbox: @inbox, event: @event).perform
      conversation = contact_inbox.conversations.last || contact_inbox.conversations.create!(
        account_id: @inbox.account_id,
        inbox_id: @inbox.id,
        contact_id: contact_inbox.contact_id,
        extensions: {
          schema_version: 1,
          group: @event[:group].merge('external_id' => @event[:group_id]),
          provider: @event[:provider]
        }
      )
      conversation.update!(team_id: routing_team_id) if routing_team_id

      extensions = @event[:extensions].deep_stringify_keys
      extensions['schema_version'] ||= 1
      extensions['kind'] ||= @event[:kind]
      # Keep the sender identity separate from provider callback metadata.
      # The dashboard uses extensions.actor for the name and avatar.
      extensions['actor'] = @event[:actor]
      extensions['provider'] = @event[:provider_data].merge('provider' => @event[:provider])

      conversation.messages.create!(
        account_id: @inbox.account_id,
        inbox_id: @inbox.id,
        message_type: :incoming,
        content: @event[:content],
        content_type: @event[:content_type],
        sender: contact_inbox.contact,
        external_event_id: @event[:external_event_id],
        source_id: @event[:external_message_id],
        extensions: extensions
      )
    end

    private

    def filtered_event?
      config = @inbox.channel.provider_config || {}
      group_id = @event[:group_id].to_s
      owner_id = (@event.dig(:group, 'owner_id') || @event.dig(:group, 'owner_external_id') || @event.dig(:actor, 'external_id')).to_s
      allowed_groups = Array(config['allowed_group_ids']).map(&:to_s)
      allowed_owners = Array(config['allowed_group_owners']).map(&:to_s)
      # Ignore rules always take precedence over allow rules.
      return true if Array(config['ignored_group_ids']).map(&:to_s).include?(group_id)

      # The allow lists are combined with OR semantics. If either list matches,
      # the event is accepted; when both are empty, all groups are accepted.
      allowed_match = allowed_groups.include?(group_id) || allowed_owners.include?(owner_id)
      return true if (allowed_groups.any? || allowed_owners.any?) && !allowed_match

      false
    end

    def routing_team_id
      rules = Array(@inbox.channel.provider_config&.[]('routing_rules'))
      rule = rules.find do |item|
        next false unless item.is_a?(Hash)
        groups = Array(item['group_ids']).map(&:to_s)
        owners = Array(item['group_owners']).map(&:to_s)
        (groups.empty? || groups.include?(@event[:group_id].to_s)) &&
          (owners.empty? || owners.include?(@event.dig(:group, 'owner_id').to_s))
      end
      team_id = rule && rule['team_id']
      team_id if team_id && @inbox.account.teams.exists?(id: team_id)
    end

    def existing_message
      return if @event[:external_event_id].blank?

      @inbox.messages.find_by(external_event_id: @event[:external_event_id])
    end

    def mark_recalled_message
      message = @inbox.messages.find_by(external_event_id: @event[:recalled_message_id])
      return unless message

      message.deleted = true
      message.save!
      message
    end
  end
end
