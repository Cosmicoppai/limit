
# Limit Gem

Gem that provides flexible, Redis-backed rate limiting utilities. It supports Fixed Window, Rolling Window (Sliding Log), and Token Bucket strategies to control the number of allowed requests for a given identifier within a time window or with a steady refill rate.

You can define rate-limiting rules dynamically using a lambda and configure Redis via environment variables (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD) or bypassing connection details directly.

This gem is ideal for APIs, background jobs, or any system that needs simple, efficient throttling logic.

## Installation

To install the gem and add it to your application's Gemfile, execute:

```bash
$ bundle add co-limit
```

If you are not using Bundler, you can install the gem directly by running:

```bash
$ gem install co-limit
```

### Supported Rate Limiters:

- **Fixed Window Rate Limiter**:
  Allows a specified number of requests within a fixed time window. This method can cause burst traffic as it doesn't account for requests made outside of the window until it resets.

- **Rolling Window Rate Limiter**:
  Uses a sliding window mechanism, where only requests made within the last `n` seconds are counted. It provides more consistent traffic flow but can be more resource-intensive.

- **Token Bucket Rate Limiter**:
  Implements the classic token bucket algorithm. A bucket with fixed capacity refills tokens at a steady rate, allowing short bursts up to the bucket capacity while enforcing long‑term average throughput.

## Usage

### Examples

#### Rolling Window Example
Here's an example of how to use the rolling window rate limiter in your application:

```ruby
sync_limit_calculator = lambda do |key| 
  pms_name = key.split(':').last.to_sym
  SITE_LIMITS.fetch(pms_name, :default)
end

rate_limiter = Limit::RollingWindowRateLimiter.new(
  identifier_prefix: 'access', 
  limit_calculator: sync_limit_calculator,
  host: '127.0.0.1', 
  port: 6379, 
  password: 'abcd1234'
)

key = '007:x'
success_count = 0
a = Time.now
11.times do
  allowed = rate_limiter.allowed?(key)
  success_count += 1 if allowed
end

sleep 5 - (Time.now - a) + 0.5  # wait until the next window
allowed = rate_limiter.allowed?(key)  # request will be allowed
success_count += 1 if allowed

puts "Success count: #{success_count}"  # Expected to be 11
```

#### Fixed Window Example

```ruby
# Map keys to a fixed-window limit of N requests per M seconds
SITE_LIMITS = {
  x: { max_requests: 10, window_seconds: 5 },   # 10 requests per 5 seconds
  default: { max_requests: 10, window_seconds: 60 }
}.freeze

calc = lambda do |key|
  plan = key.split(":").last.to_sym rescue :default
  SITE_LIMITS.fetch(plan, SITE_LIMITS[:default])
end

limiter = Limit::FixedWindowRateLimiter.new(
  identifier_prefix: "access",
  limit_calculator: calc
)

key = "user123:x"  # => will map to { max_requests: 10, window_seconds: 5 }

# Consume up to the window limit
allowed = 0
12.times { allowed += 1 if limiter.allowed?(key) }
puts allowed  # => 10

# Wait until the next aligned fixed window begins to reset the counter
window = 5
now = Time.now
sleep(window - (now.to_i % window) + 0.5)

puts limiter.allowed?(key)  # => true (window reset)
```

#### Token Bucket Example

```ruby
# Choose a plan via the key suffix, then map it to a token bucket config
PLANS = {
  basic:   { bucket_capacity: 3, refill_rate: 1, refill_interval: 1 },  # 3 burst, ~1 req/s
  premium: { bucket_capacity: 10, refill_rate: 5, refill_interval: 1 }  # 10 burst, ~5 req/s
}.freeze

calc = lambda do |key|
  plan = key.split(":").last.to_sym rescue :basic
  PLANS.fetch(plan, PLANS[:basic])
end

limiter = Limit::TokenBucketRateLimiter.new(
  identifier_prefix: "access",   # identifier_prefix is used to namespace keys in Redis (consistent across all limiters)
  limit_calculator: calc
)

key = "user123:basic"            # the final Redis key will be "access:user123:basic" via identifier_prefix

# Use up to capacity immediately
3.times { puts limiter.allowed?(key) }  # => true, true, true
puts limiter.allowed?(key)              # => false (bucket empty)

sleep 1.2                               # wait ~1s to refill ~1 token
puts limiter.allowed?(key)              # => true
```

### Key Points:

- **identifier_prefix**: A namespace prefix for Redis keys (e.g., `"access"`).
- **limit_calculator**: A `Lambda` that takes a key (e.g., `"user_id:site_name"`) and returns a hash with `max_requests` and `window_seconds`.

### Limit Hash Structure by Limiter

Your `limit_calculator` lambda must return a hash whose expected keys depend on the limiter you use:

- FixedWindowRateLimiter and RollingWindowRateLimiter expect:
  `{ max_requests: Integer, window_seconds: Integer }`

- TokenBucketRateLimiter expects:
  `{ bucket_capacity: Integer, refill_rate: Integer, refill_interval: Integer }`

  Meaning: `refill_rate` tokens are added every `refill_interval` seconds (e.g., `refill_rate: 1, refill_interval: 1` = 1 token/second; `refill_rate: 3, refill_interval: 2` = 1.5 tokens/second effective rate). All values must be positive integers.

Notes:
- Redis keys are stored as "#{identifier_prefix}:#{key}". Choose concise, stable keys; e.g., identifier_prefix: "access" and key: "user_id:plan" → "access:user_id:plan".
- Ensure the keys you pass are unique per entity you want to limit (e.g., "access:user_id:plan").
- For Token Bucket, the Redis TTL is kept around the refill interval so buckets expire when inactive.

### Redis Configuration

You can configure the Redis connection either by passing the connection details as arguments or by setting environment variables.

- **Option 1**: Pass the connection details directly when initializing the limiter:

  ```ruby
  rate_limiter = Limit::RollingWindowRateLimiter.new(
    identifier_prefix: 'access', 
    limit_calculator: sync_limit_calculator,
    host: '127.0.0.1', 
    port: 6379, 
    password: 'abcd1234'
  )
  ```

- **Option 2**: Set the connection details as environment variables (`REDIS_HOST`, `REDIS_PORT`, and `REDIS_PASSWORD`), and the gem will automatically use them:

  ```bash
  export REDIS_HOST='127.0.0.1'
  export REDIS_PORT='6379'
  export REDIS_PASSWORD='abcd1234'
  ```

  In this case, the gem will use these environment variables to establish the Redis connection.

## Development

After checking out the repo, install the dependencies by running:

```bash
$ bin/setup
```

To run tests, execute:

```bash
$ rake test
```

For an interactive prompt, run:

```bash
$ bin/console
```

To install the gem locally:

```bash
$ bundle exec rake install
```

To release a new version, update the version number in `version.rb`, and run:

```bash
$ bundle exec rake release
```

This will create a git tag for the new version, push the tag, and push the gem to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/cosmicoppai/limit. This project aims to be a safe, welcoming space for collaboration. Contributors are expected to adhere to the [code of conduct](https://github.com/cosmicoppai/limit/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Limit project's codebases, issue trackers, chat rooms, and mailing lists is expected to follow the [code of conduct](https://github.com/cosmicoppai/limit/blob/main/CODE_OF_CONDUCT.md).
