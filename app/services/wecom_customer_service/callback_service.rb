require 'rexml/document'

class WecomCustomerService::CallbackService
  def initialize(channel:)
    @channel = channel
  end

  def verification_response(params)
    params = normalized_params(params)
    encrypted = params[:echostr].to_s
    verify_signature!(encrypted, params)
    decrypt(encrypted)
  end

  def callback_event(request)
    payload = parse_payload(request.raw_post)
    verify_signature!(payload[:encrypted], request.parameters)
    event = decrypt_payload(payload)
    validate_event!(event)

    {
      token: event.fetch('Token'),
      open_kfid: event.fetch('OpenKfId')
    }
  end

  private

  def normalized_params(params)
    source = params.respond_to?(:to_unsafe_h) ? params.to_unsafe_h : params.to_h
    source.with_indifferent_access
  end

  def parse_payload(raw_body)
    body = raw_body.to_s.strip
    return parse_json(body) if body.start_with?('{')

    xml = REXML::Document.new(body)
    root = xml.root
    encrypted = root&.elements['Encrypt']&.text.to_s.presence
    { encrypted: encrypted, data: xml_payload(root) }
  rescue REXML::ParseException => e
    raise ArgumentError, "invalid WeCom callback payload: #{e.message}"
  end

  def parse_json(body)
    data = JSON.parse(body).deep_stringify_keys
    { encrypted: data['Encrypt'] || data['encrypt'], data: data }
  rescue JSON::ParserError => e
    raise ArgumentError, "invalid WeCom callback payload: #{e.message}"
  end

  def xml_payload(root)
    return {} unless root

    root.elements.each_with_object({}) do |element, payload|
      payload[element.name] = element.text.to_s
    end
  end

  def decrypt_payload(payload)
    return payload[:data] if payload[:encrypted].blank?

    plain_text = decrypt(payload[:encrypted])
    plain_text.lstrip.start_with?('<') ? xml_payload(REXML::Document.new(plain_text).root) : JSON.parse(plain_text).deep_stringify_keys
  rescue REXML::ParseException, JSON::ParserError => e
    raise ArgumentError, "invalid decrypted WeCom callback payload: #{e.message}"
  end

  def validate_event!(event)
    raise ArgumentError, 'invalid WeCom callback event' unless event['Event'].to_s == 'kf_msg_or_event'
    raise ArgumentError, 'WeChat customer service does not match this channel' unless event['OpenKfId'].to_s == @channel.open_kfid.to_s
    raise ArgumentError, 'invalid WeCom callback token' if event['Token'].blank?
    return if @channel.corp_id.blank? || event['ToUserName'].blank?
    return if event['ToUserName'].to_s == @channel.corp_id.to_s

    raise ArgumentError, 'WeCom callback does not match this corporation'
  end

  def verify_signature!(encrypted, params)
    timestamp = params[:timestamp].to_s
    nonce = params[:nonce].to_s
    signature = params[:msg_signature].presence || params[:signature].to_s
    expected = Digest::SHA1.hexdigest([@channel.callback_token, timestamp, nonce, encrypted.to_s].sort.join)
    return if signature.present? && ActiveSupport::SecurityUtils.secure_compare(expected, signature)

    raise ArgumentError, 'invalid WeCom callback signature'
  end

  def decrypt(encrypted)
    key = decode_aes_key
    raise ArgumentError, 'invalid WeCom callback AES key' unless key.bytesize == 32

    cipher = OpenSSL::Cipher.new('AES-256-CBC')
    cipher.decrypt
    cipher.padding = 0
    cipher.key = key
    cipher.iv = key[0, 16]
    plain_text = cipher.update(decode_base64(encrypted, 'encrypted payload')) + cipher.final
    plain_text = unpad(plain_text)
    raise ArgumentError, 'invalid WeCom callback encryption payload' if plain_text.bytesize < 20

    message_length = plain_text.byteslice(16, 4).unpack1('N')
    raise ArgumentError, 'invalid WeCom callback encryption payload' if message_length > plain_text.bytesize - 20

    plain_text.byteslice(20, message_length).to_s.force_encoding(Encoding::UTF_8)
  rescue ArgumentError, OpenSSL::Cipher::CipherError => e
    raise ArgumentError, "invalid WeCom callback encryption: #{e.message}"
  end

  def decode_aes_key
    encoded = @channel.encoding_aes_key.to_s.strip
    unless encoded.match?(/\A[A-Za-z0-9]{43}\z/)
      raise ArgumentError, 'invalid EncodingAESKey format'
    end

    Base64.decode64("#{encoded}=")
  rescue ArgumentError => e
    raise ArgumentError, "invalid EncodingAESKey base64: #{e.message}"
  end

  def decode_base64(value, label, append_padding: false)
    encoded = value.to_s.strip
    encoded = encoded.delete('=') + '=' if append_padding
    Base64.strict_decode64(encoded)
  rescue ArgumentError => e
    raise ArgumentError, "invalid #{label} base64: #{e.message}"
  end

  def unpad(value)
    padding_length = value.getbyte(-1).to_i
    raise ArgumentError, 'invalid WeCom callback padding' unless (1..32).cover?(padding_length)
    raise ArgumentError, 'invalid WeCom callback padding' unless value.bytesize >= padding_length
    return value if value.byteslice(-padding_length, padding_length).bytes.all? { |byte| byte == padding_length }

    raise ArgumentError, 'invalid WeCom callback padding'
  end
end
