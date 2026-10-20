class WecomCustomerService::ApiError < StandardError
  attr_reader :operation, :errcode

  def initialize(operation:, errcode:, errmsg:)
    @operation = operation
    @errcode = errcode.to_i
    super("WeCom #{operation} returned error #{errcode}: #{errmsg}")
  end

  def servicer_offline?
    errcode == 95019
  end
end
