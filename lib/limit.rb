# frozen_string_literal: true

require 'redis'
require 'logger'


module Limit

  # Base Class, implementing:
  # - Method to connect with redis
  # - Signature for limit_calculator
  class BaseLimiter
    attr_reader :limit_calculator, :identifier_prefix

    @redis = nil
    @logger = Logger.new($stdout)

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

      private

      def create_connection(host:, port:, password:)
        if password && !password.empty?
          Redis.new(host: host, port: port, password: password)
        else
          Redis.new(host: host, port: port)
        end
      end

    end

    def initialize(identifier_prefix:, limit_calculator:, host: nil, port: nil, password: nil)

    # @param identifier_prefix: [String] A namespace prefix for redis keys for this limiter instance
    # @param limit_calculator: [Proc] A method that takes a key(String) and returns hash: {max_requests: Integer, window_seconds: Integer}

      unless identifier_prefix.is_a?(String) && !identifier_prefix.empty?
        raise ArgumentError, 'identifier_prefix must be a non-empty String'
      end

      raise ArgumentError, 'limit_calculator must be a Proc' unless limit_calculator.is_a?(Proc)

      # Will be using the same connection across all instance unless wanted to connect to diff instance of redis

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

    end

    def allowed?(key)
      raise NotImplementedError "#{self.class.name} must implement the allowed? method"
    end

    def get_key(prefix)
      raise NotImplementedError "#{self.class.name} must implement the get_key() method"
    end


    protected

    def get_current_limit(key)
      limit_data = @limit_calculator.call(key)

      unless limit_data.is_a?(Hash) && limit_data[:max_requests].is_a?(Integer) && limit_data[:max_requests].positive? &&
             limit_data[:window_seconds].is_a?(Integer) && limit_data[:window_seconds].positive?

        raise ArgumentError, "Limit calculator for key '#{key}' returned invalid data: #{limit_data.inspect}. Expected { max_requests: Integer > 0, window_seconds: Integer > 0 }"
      end

      limit_data
    end

    def redis_pipeline(&block)
      begin
        @redis.pipelined { |pipe| block.call(pipe) }
      rescue Redis::CommandError => e
        @logger.error(e.message)
      end
    end

    def current_micros
      (Time.now.to_f * 1_000_000).to_i
    end


  end


  # ====================================================================================================================

  # Fixed Window Rate Limiter, allows n of request in a fixed window
  # ALERT: There is a chance of bursts/spike in this method, so use it with caution
  class FixedWindowRateLimiter < BaseLimiter
    def allowed?(key)
      limit_data = get_current_limit(key)
      max_requests = limit_data[:max_requests]
      window_seconds = limit_data[:window_seconds]

      window_key = get_key(key, window_seconds)

      results = redis_pipeline do |pipe|
        # This is for simplicity as incr handles both creation and incrementing, rather than waiting on some read
        # using the pipeline, the whole operation would also be atomic, as redis is single threaded and both queries are send in one trip
        # https://redis.io/docs/latest/develop/use/pipelining/
        pipe.incr(window_key)
        pipe.expire(window_key, window_seconds)
      end

      results[0] <= max_requests
    end

    def get_key(prefix, window_seconds)
      time_window = (Time.now.to_i / window_seconds) * window_seconds
      "#{@identifier_prefix}:#{prefix}:#{time_window.to_s}"
    end
  end

  # RollingWindow Rate limiter implemented using Sliding Log, allows n no of requests in rolling window
  class RollingWindowRateLimiter < BaseLimiter
    def allowed?(key)
      limit_data = get_current_limit(key)
      max_requests = limit_data[:max_requests]
      window_seconds = limit_data[:window_seconds]

      set_key = get_key(key)

      curr_micros = current_micros

      window_start_micros = curr_micros - (window_seconds*1_000_000)

      results = redis_pipeline do |pipe|
        # uses sorted set
        # https://redis.io/glossary/redis-sorted-sets/
        pipe.zremrangebyscore(set_key, 0, window_start_micros)
        pipe.zadd(set_key, curr_micros, curr_micros.to_s)
        pipe.zcard(set_key)
        pipe.expire(set_key, window_seconds)
      end

      results[2] <= max_requests
    end

    def get_key(prefix)
      "#{@identifier_prefix}:#{prefix}"
    end
  end


end
