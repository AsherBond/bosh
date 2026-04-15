require 'spec_helper'

module Bosh::Director::Blobstore
  describe UuidValidation do
    describe '.valid_uuid?' do
      it 'returns true for lowercase UUIDs from SecureRandom.uuid' do
        id = SecureRandom.uuid
        expect(described_class.valid_uuid?(id)).to be(true)
      end

      it 'returns true for uppercase hex' do
        expect(described_class.valid_uuid?('A0EEBC99-9C0B-4EF8-BB6D-6BB9BD380A11')).to be(true)
      end

      it 'returns false for non-UUID strings' do
        expect(described_class.valid_uuid?('cafe')).to be(false)
        expect(described_class.valid_uuid?('deadbeef')).to be(false)
        expect(described_class.valid_uuid?('')).to be(false)
      end

      it 'returns false for non-strings' do
        expect(described_class.valid_uuid?(nil)).to be(false)
        expect(described_class.valid_uuid?(123)).to be(false)
      end
    end
  end
end
