module GroupMessaging
  module Providers
    class Feishu < Base
      def normalize_event(payload)
        GroupMessaging::EventNormalizer.normalize(payload, provider: 'feishu')
      end
    end
  end
end
