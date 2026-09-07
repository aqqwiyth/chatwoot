module GroupMessaging
  module Providers
    class Dingtalk < Base
      def normalize_event(payload)
        GroupMessaging::EventNormalizer.normalize(payload, provider: 'dingtalk')
      end
    end
  end
end
