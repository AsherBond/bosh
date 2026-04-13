module Bosh::Director
  module Blobstore
    # Validates UUIDs are (8-4-4-4-12 hex):
    # - Ruby: SecureRandom.uuid
    # - Golang: github.com/nu7hatch/gouuid
    module UuidValidation
      UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze

      def self.valid_uuid?(value)
        UUID_PATTERN.match?(value.to_s)
      end
    end
  end
end
