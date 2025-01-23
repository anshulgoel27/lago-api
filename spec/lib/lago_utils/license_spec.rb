# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LagoUtils::License do
  subject(:license) { described_class.new(url) }

  let(:url) { 'https://license.lago' }

  before do
    ENV['LAGO_LICENSE'] = 'test-license'
  end

  describe '#verify' do
    before do
      license.verify
    end

    it 'always sets premium to true' do
      expect(license).to be_premium
    end
  end
end
