# Minimal stand-in for the redis-client connection Sidekiq.redis yields,
# covering the hash commands JobMetrics uses. CI's unit test job has no Redis.
class FakeHashRedis
  attr_reader :hashes

  def initialize
    @hashes = Hash.new { |h, k| h[k] = {} }
  end

  def pipelined
    yield self
  end

  def call(command, key, *args)
    hash = @hashes[key]
    case command
    when "HINCRBY" then hash[args[0]] = (hash[args[0]].to_i + args[1].to_i).to_s
    when "HINCRBYFLOAT" then hash[args[0]] = (hash[args[0]].to_f + args[1].to_f).to_s
    when "HSET" then hash[args[0]] = args[1].to_s
    when "HGETALL" then hash.dup
    when "DEL" then @hashes.delete(key) ? 1 : 0
    else raise ArgumentError, "FakeHashRedis does not support #{command}"
    end
  end
end
