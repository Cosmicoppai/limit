
# Limit Gem

Gem that provides flexible, Redis-backed rate limiting utilities. It supports both Fixed Window and Rolling Window (Sliding Log) strategies, to easily control the number of allowed requests for a given identifier within a time window.

You can define rate-limiting rules dynamically using a Proc, and configure Redis via environment variables (REDIS_HOST, REDIS_PORT, REDIS_PASSWORD) or by passing connection details directly.

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

## Usage

### Example Usage

Here's an example of how to use the rate limiter in your application:

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

### Key Points:

- **identifier_prefix**: A namespace prefix for Redis keys (e.g., `"access"`).
- **limit_calculator**: A `Proc` that takes a key (e.g., `"user_id:site_name"`) and returns a hash with `max_requests` and `window_seconds`.

### Supported Rate Limiters:

- **Fixed Window Rate Limiter**:
  Allows a specified number of requests within a fixed time window. This method can cause burst traffic as it doesn't account for requests made outside of the window until it resets.

- **Rolling Window Rate Limiter**:
  Uses a sliding window mechanism, where only requests made within the last `n` seconds are counted. It provides more consistent traffic flow but can be more resource-intensive.

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
