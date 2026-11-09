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
    @channel.update!(reception_servicer_names: @names)
    @client.list_servicers.fetch('servicer_list')
  end
end
