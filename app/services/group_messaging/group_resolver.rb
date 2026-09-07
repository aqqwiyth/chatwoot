module GroupMessaging
  class GroupResolver
    def initialize(inbox:, event:)
      @inbox = inbox
      @event = event
    end

    def perform
      raise ArgumentError, 'group_id is required' if @event[:group_id].blank?

      ContactInboxWithContactBuilder.new(
        inbox: @inbox,
        source_id: @event[:group_id],
        contact_attributes: {
          name: @event.dig(:group, 'display_name') || @event[:group_id],
          contact_type: 'group',
          extensions: {
            schema_version: 1,
            provider: @event[:provider],
            external_group_id: @event[:group_id]
          }.merge(@event[:group])
        }
      ).perform
    end
  end
end
