module GroupMessaging
  module Providers
    class Wecom < Base
      def normalize_event(payload)
        GroupMessaging::EventNormalizer.normalize(payload, provider: 'wecom')
      end
    end
  end
end
