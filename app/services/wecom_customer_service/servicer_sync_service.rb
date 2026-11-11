class WecomCustomerService::ServicerSyncService
  def initialize(channel:, client:, userids:, names:)
    @channel = channel
    @client = client
    @userids = userids.uniq
    @names = names
  end

  def perform
    current = @client.list_servicers.fetch('servicer_list').filter_map { |servicer| servicer['userid'].presence }
    (@userids - current).each_slice(100) { |batch| @client.change_servicers(operation: 'add', userids: batch) }
    (current - @userids).each_slice(100) { |batch| @client.change_servicers(operation: 'del', userids: batch) }
    @channel.update!(reception_servicer_names: servicer_names)
    @client.list_servicers.fetch('servicer_list')
  end

  private

  # Names are stored as a snapshot of the WeCom directory: a rename on the platform side is only
  # picked up by syncing the reception settings again.
  def servicer_names
    @userids.index_with { |userid| resolve_name(userid) }.compact
  end

  def resolve_name(userid)
    @client.get_user(userid: userid)['name'].presence
  rescue WecomCustomerService::ApiError
    @names[userid].presence
  end
end
