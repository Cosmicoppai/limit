local key = KEYS[1]
local window_seconds = tonumber(ARGV[1])
local max_requests = tonumber(ARGV[2])

local curr_time = redis.call('TIME')
local curr_sec = tonumber(curr_time[1])

local time_window = math.floor(curr_sec / window_seconds) * window_seconds

local window_key = key .. ":" .. tostring(time_window)

-- This is for simplicity as incr handles both creation and incrementing, rather than waiting on some read
local count = redis.call('incr', window_key)

redis.call('expire', window_key, window_seconds)

if count <= max_requests then
    return 1
else
    return 0
end