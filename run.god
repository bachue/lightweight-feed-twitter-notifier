God.watch do |w|
  w.name = 'ruby-china-twitter-notifier'
  w.start = "cd #{File.expand_path(File.dirname(__FILE__))} && thor sync:continuously"
  w.keepalive
end
