module GroupMessaging
  module Providers
    class Base
      attr_reader :channel

      def initialize(channel:)
        @channel = channel
      end

      def normalize_event(_payload)
        raise NotImplementedError
      end

      def verify!(request)
        secret = channel.provider_config['webhook_secret']
        return true if secret.blank?

        signature = request.headers['X-Group-Signature'].to_s.sub(/^sha256=/, '')
        expected = OpenSSL::HMAC.hexdigest('sha256', secret, request.raw_post)
        raise ArgumentError, 'invalid webhook signature' unless ActiveSupport::SecurityUtils.secure_compare(expected, signature)

        true
      end

      def send_message(message)
        endpoint = channel.provider_config['send_url'].presence || channel.provider_config['send_base_url']
        raise ArgumentError, 'provider send_url is not configured' if endpoint.blank?

        response = HTTParty.post(
          endpoint,
          headers: { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{channel.provider_config['access_token']}" },
          body: {
            group_id: message.conversation.contact_inbox.source_id,
            content: message.content,
            content_type: message.content_type,
            extensions: message.extensions
          }.to_json
        )
        raise ArgumentError, "provider send failed: #{response.code}" unless response.success?

        response.parsed_response['message_id'] || response.parsed_response['id']
      end

      def capabilities
        channel.capabilities || {}
      end
    end
  end
end
