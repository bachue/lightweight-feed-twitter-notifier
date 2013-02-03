God.watch do |w|
  w.name = 'ruby-china-twitter-notifier'
  w.dir = File.expand_path(File.dirname(__FILE__))
  w.start = "thor sync:continuously"
  w.keepalive
end
