God.watch do |w|
  w.name = 'ruby-china-twitter-notifier'
  w.dir = File.expand_path(File.dirname(__FILE__))
  w.start = "thor sync:continuously"
  w.keepalive
  w.log = 'log/god.log'
  w.restart_if do |restart|
    restart.condition(:memory_usage) do |c|
      c.interval = 5.seconds
      c.above = 30.megabytes
      c.times = [3, 5]
    end
  end
end
