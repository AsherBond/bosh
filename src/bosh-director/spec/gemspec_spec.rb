require 'spec_helper'
require 'rubygems/package'

module Bosh::Director
  describe 'gem' do
    let(:name) { 'bosh-director' }
    let(:spec) { Gem::Specification.load(File.expand_path("../#{name}.gemspec", __dir__)) }

    it 'validates' do
      Gem::DefaultUserInteraction.use_ui(Gem::SilentUI.new) do
        expect(spec.validate).to be_truthy
      end
    end
  end
end
