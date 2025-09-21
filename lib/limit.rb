# frozen_string_literal: true

require 'redis'
require 'logger'


module Limit

  # Base Class, implementing:
  # - Method to connect with redis
  # - Signature for limit_calculator
  class BaseRateLimiter
    attr_reader :limit_calculator, :identifier_prefix

    @redis = nil
    @logger = Logger.new($stdout)

    REQUIRED_KEYS = %i[max_requests window_seconds].freeze

    class << self

      def connection
        host = ENV['REDIS_HOST']
        port = ENV['REDIS_PORT']
        password = ENV['REDIS_PASSWORD']
        @redis ||= create_connection(host: host, port: port, password: password)
      end

      def logger
        @logger ||= Logger.new($stdout)
      end

      def load_script
        script_name = name.split('::')[1].chomp('RateLimiter')
        script_path = File.expand_path("scripts/#{script_name}.lua", __dir__)
        @script_sha = @redis.script(:load, File.read(script_path))
      end

      def script_sha
        @script_sha
      end

      private

      def create_connection(host:, port:, password:)
        if password && !password.empty?
          Redis.new(host: host, port: port, password: password)
        else
          logger.warn('Connecting without password')
          Redis.new(host: host, port: port)
        end
      end

    end

    def initialize(identifier_prefix:, limit_calculator:, host: nil, port: nil, password: nil)

      # @param identifier_prefix: [String] A namespace prefix for redis keys for this limiter instance
      # @param limit_calculator: Lambda that takes a key(String) and returns hash: {max_requests: Integer, window_seconds: Integer}
      # But diff implementation can update the hash struct

      unless identifier_prefix.is_a?(String) && !identifier_prefix.empty?
        raise ArgumentError, 'identifier_prefix must be a non-empty String'
      end

      raise ArgumentError, 'limit_calculator must be a Lambda' unless limit_calculator.lambda?

      # Will be using the same connection across all instances unless wanted to connect to diff instance of redis

      @redis = if host && port && password
                 self.class.send(:create_connection, host: host, port: port, password: password)
               else
                 self.class.connection
               end

      @identifier_prefix = identifier_prefix
      @limit_calculator = limit_calculator
      @logger = self.class.logger

      begin
        @redis.ping
        @logger.info("Successfully connected to Redis @ #{@redis.connection[:host]}:#{@redis.connection[:port]}")
      rescue Redis::BaseError => e
        @logger.error("Error connecting to Redis: #{e.message}")
        raise e
      end

      self.class.load_script
    end

    def allowed?(key)
      raise NotImplementedError "#{self.class.name} must implement the allowed? method"
    end

    def get_key(key)
      "#{@identifier_prefix}:#{key}"
    end


    protected

    def required_keys
      self.class::REQUIRED_KEYS
    end

    def get_current_limit(key)
      limit_data = @limit_calculator.call(key)

      required_keys.all? do |key|
        unless limit_data[key].is_a?(Integer) && limit_data[key].positive?
          raise ArgumentError, "Limit calculator for key '#{key}' returned invalid data: #{limit_data.inspect}.\n
          Expected #{required_keys}"
        end
      end

      limit_data
    end

    def eval_sha(key, argv)
      attempts ||= 0
      begin
        @redis.evalsha(self.class.script_sha, key, argv)
      rescue Redis::CannotConnectError, Redis::TimeoutError, Redis::ConnectionError => e
        if attempts < 3
          @logger.warn(e.message)
          @redis = self.class.connection
          attempts += 1
          retry
        else
          @logger.error("Error connecting to Redis: #{e.message}")
        end
      rescue Redis::CommandError => e
        if e.message.start_with?("NOSCRIPT")
          self.class.load_script
          retry
        else
          @logger.error(e.message)
        end
      rescue Redis::BaseError => e
        @logger.error(e.message)
      end
    end

  end


  # ====================================================================================================================

  # Fixed Window Rate Limiter, allows n of request in a fixed window
  # ALERT: There is a chance of bursts/spike in this method, so use it with caution
  class FixedWindowRateLimiter < BaseRateLimiter
    def allowed?(key)
      limit_data = get_current_limit(key)
      result = eval_sha(
        [get_key(key)],
        [
          limit_data[:window_seconds],
          limit_data[:max_requests]
        ]
      )
      result == 1
    end
  end

  # RollingWindow Rate limiter, implemented using Sliding Log, allows n no of requests in a rolling window
  class RollingWindowRateLimiter < BaseRateLimiter
    def allowed?(key)
      limit_data = get_current_limit(key)
      result = eval_sha(
        [get_key(key)],
        [
          limit_data[:window_seconds],
          limit_data[:max_requests]
        ]
      )
      result == 1
    end
  end

  # TokenBucketRateLimiter implements the token bucket algorithm that'll allow the steady refill rate
  class TokenBucketRateLimiter < BaseRateLimiter

    # limit_calculator: Lambda that takes a key(String) and returns hash:
    # {bucket_capacity: Integer, refill_rate: Integer, refill_interval: Integer}

    REQUIRED_KEYS = %i[bucket_capacity refill_rate refill_interval].freeze

    def allowed?(key)
      limit_data = get_current_limit(key)
      result = eval_sha(
        [get_key(key)],
        [
          limit_data[:bucket_capacity],
          limit_data[:refill_rate],
          limit_data[:refill_interval]
        ]
      )
      result == 1
    end

  end

end
