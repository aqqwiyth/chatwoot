require 'rails_helper'

RSpec.describe WecomCustomerService::CallbackService do
  let(:channel) do
    instance_double(
      Channel::WecomCustomerService,
      callback_token: 'callback-token',
      encoding_aes_key: ('A' * 42) + 'B',
      open_kfid: 'wk-customer-service',
      corp_id: 'ww-corp-id'
    )
  end
  let(:service) { described_class.new(channel: channel) }

  it 'returns the sync token from a signed customer service callback' do
    body = <<~XML
      <xml>
        <ToUserName><![CDATA[ww-corp-id]]></ToUserName>
        <Event><![CDATA[kf_msg_or_event]]></Event>
        <Token><![CDATA[sync-token]]></Token>
        <OpenKfId><![CDATA[wk-customer-service]]></OpenKfId>
      </xml>
    XML
    timestamp = '1710000000'
    nonce = 'nonce'
    signature = Digest::SHA1.hexdigest(['callback-token', timestamp, nonce, ''].sort.join)
    request = instance_double(
      ActionDispatch::Request,
      raw_post: body,
      parameters: { timestamp: timestamp, nonce: nonce, msg_signature: signature }
    )

    expect(service.callback_event(request)).to eq(token: 'sync-token', open_kfid: 'wk-customer-service')
  end

  it 'rejects a callback with an invalid signature' do
    request = instance_double(
      ActionDispatch::Request,
      raw_post: '<xml><Event>kf_msg_or_event</Event></xml>',
      parameters: { timestamp: '1710000000', nonce: 'nonce', msg_signature: 'invalid' }
    )

    expect { service.callback_event(request) }.to raise_error(ArgumentError, /signature/)
  end

  it 'decrypts callbacks using WeCom 32-byte PKCS#7 padding' do
    message = <<~XML.strip
      <xml><ToUserName>ww-corp-id</ToUserName><Event>kf_msg_or_event</Event><Token>sync-token</Token><OpenKfId>wk-customer-service</OpenKfId></xml>
    XML
    key = Base64.decode64("#{channel.encoding_aes_key}=")
    frame = ('r' * 16) + [message.bytesize].pack('N') + message + 'ww-corp-id'
    padding_length = 32 - (frame.bytesize % 32)
    frame = frame + (padding_length.chr * padding_length)
    cipher = OpenSSL::Cipher.new('AES-256-CBC')
    cipher.encrypt
    cipher.padding = 0
    cipher.key = key
    cipher.iv = key[0, 16]
    encrypted = Base64.strict_encode64(cipher.update(frame) + cipher.final)

    expect(service.send(:decrypt, encrypted)).to eq(message)
  end
end
