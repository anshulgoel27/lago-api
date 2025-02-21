# frozen_string_literal: true

module LagoUtils
  class License
    def initialize(url)
      @url = url
      @premium = true
    end

    def verify
      # return if ENV['LAGO_LICENSE'].blank?

      # http_client = LagoHttpClient::Client.new("#{url}/verify/#{ENV["LAGO_LICENSE"]}")
      # response = http_client.get

      @premium = true
      return true
    end

    def premium?
      premium
    end

    private

    attr_reader :url, :premium
  end
end
