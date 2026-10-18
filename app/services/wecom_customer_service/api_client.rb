require 'faraday/multipart'
require 'tempfile'
require 'uri'

class WecomCustomerService::ApiClient
  API_BASE_URL = 'https://qyapi.weixin.qq.com/cgi-bin'.freeze
  DownloadedMedia = Struct.new(:io, :filename, :content_type, keyword_init: true)

  def initialize(channel:)
    @channel = channel
  end

  def sync_messages(cursor:, callback_token:)
    response = HTTParty.post(
      "#{API_BASE_URL}/kf/sync_msg",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json' },
      body: {
        cursor: cursor,
        token: callback_token,
        limit: 1000,
        voice_format: 0,
        open_kfid: @channel.open_kfid
      }.compact.to_json,
      timeout: 10
    )

    api_payload(response, 'sync_msg')
  end

  def get_customer(external_userid:)
    response = HTTParty.post(
      "#{API_BASE_URL}/kf/customer/batchget",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json' },
      body: {
        external_userid_list: [external_userid],
        need_enter_session_context: 1
      }.to_json,
      timeout: 10
    )

    api_payload(response, 'kf/customer/batchget')
  end

  def get_service_state(external_userid:)
    response = HTTParty.post(
      "#{API_BASE_URL}/kf/service_state/get",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json' },
      body: {
        open_kfid: @channel.open_kfid,
        external_userid: external_userid
      }.to_json,
      timeout: 10
    )

    api_payload(response, 'kf/service_state/get')
  end

  def list_servicers
    response = HTTParty.get(
      "#{API_BASE_URL}/kf/servicer/list",
      query: { access_token: access_token, open_kfid: @channel.open_kfid },
      timeout: 10
    )

    api_payload(response, 'kf/servicer/list')
  end

  def transfer_service_state(external_userid:, service_state:, servicer_userid: nil)
    response = HTTParty.post(
      "#{API_BASE_URL}/kf/service_state/trans",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json' },
      body: {
        open_kfid: @channel.open_kfid,
        external_userid: external_userid,
        service_state: service_state,
        servicer_userid: servicer_userid
      }.compact.to_json,
      timeout: 10
    )

    api_payload(response, 'kf/service_state/trans')
  end

  def send_text(external_userid:, content:)
    send_message(
      external_userid: external_userid,
      payload: {
        msgtype: 'text',
        text: { content: content.to_s.truncate(2048, omission: '…') }
      }
    )
  end

  def send_media(external_userid:, media_type:, media_id:)
    send_message(
      external_userid: external_userid,
      payload: { msgtype: media_type, media_type => { media_id: media_id } }
    )
  end

  def download_media(media_id:)
    response = HTTParty.get(
      "#{API_BASE_URL}/media/get",
      query: { access_token: access_token, media_id: media_id },
      timeout: 30
    )
    raise "WeCom media download returned HTTP #{response.code}" unless response.success?

    content_type = response.headers['content-type'].to_s.split(';').first.presence
    if content_type.blank? || content_type == 'application/json' || response.body.lstrip.start_with?('{')
      payload = JSON.parse(response.body).deep_stringify_keys
      raise "WeCom media download returned error #{payload['errcode']}: #{payload['errmsg']}"
    end

    filename = media_filename(response, media_id, content_type)
    tempfile = Tempfile.new(["wecom-#{media_id}", File.extname(filename)])
    tempfile.binmode
    tempfile.write(response.body)
    tempfile.rewind

    DownloadedMedia.new(io: tempfile, filename: filename, content_type: content_type)
  rescue StandardError
    tempfile&.close!
    raise
  end

  def upload_media(file:, filename:, content_type:, media_type:)
    endpoint = "#{API_BASE_URL}/media/upload?#{URI.encode_www_form(access_token: access_token, type: media_type)}"
    response = multipart_connection.post(
      endpoint,
      media: Faraday::Multipart::FilePart.new(file, content_type, filename)
    )

    payload = JSON.parse(response.body).deep_stringify_keys
    raise "WeCom media upload returned HTTP #{response.status}" unless response.success?
    raise "WeCom media upload returned error #{payload['errcode']}: #{payload['errmsg']}" unless payload['errcode'].to_i.zero?

    payload
  end

  private

  def access_token
    Rails.cache.fetch("wecom_customer_service/access_token/#{@channel.id}", expires_in: 110.minutes) do
      response = HTTParty.get(
        "#{API_BASE_URL}/gettoken",
        query: { corpid: @channel.corp_id, corpsecret: @channel.secret },
        timeout: 10
      )
      api_payload(response, 'gettoken').fetch('access_token')
    end
  end

  def send_message(external_userid:, payload:)
    response = HTTParty.post(
      "#{API_BASE_URL}/kf/send_msg",
      query: { access_token: access_token },
      headers: { 'Content-Type' => 'application/json' },
      body: payload.merge(touser: external_userid, open_kfid: @channel.open_kfid).to_json,
      timeout: 10
    )

    api_payload(response, 'send_msg')
  end

  def multipart_connection
    @multipart_connection ||= Faraday.new do |faraday|
      faraday.request :multipart
      faraday.options.timeout = 30
    end
  end

  def media_filename(response, media_id, content_type)
    disposition = response.headers['content-disposition'].to_s
    filename = disposition[/filename\*?=(?:UTF-8''|\")?([^;\"]+)/i, 1].to_s.strip
    filename = media_id if filename.blank?
    return filename if File.extname(filename).present?

    extension = content_type.split('/').last.to_s.split('+').first
    extension = 'bin' if extension.blank?
    "#{filename}.#{extension}"
  end

  def api_payload(response, operation)
    raise "WeCom #{operation} returned HTTP #{response.code}" unless response.success?

    payload = response.parsed_response
    raise "WeCom #{operation} returned an invalid response" unless payload.is_a?(Hash)

    payload = payload.deep_stringify_keys
    return payload if payload['errcode'].to_i.zero?

    raise "WeCom #{operation} returned error #{payload['errcode']}: #{payload['errmsg']}"
  end
end
