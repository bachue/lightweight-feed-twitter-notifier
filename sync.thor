require 'thor'
require 'feedzirra'
require 'twitter'
require 'logger'
require 'timeout'
require 'active_support/all'

TWEET_MAX_LENGTH = 140
SHORT_URL_LENGTH = 23

class Sync < Thor
  desc 'all', 'Sync all new feeds from Ruby China to Twitter'
  def all
    feeds_clients.each do |name, feed_client|
      feed = feed_client[:feed]
      feed = filter_feed(feed, feed_client[:start_from])
      client = feed_client[:client]
      feed.entries.reverse.each { |entry| tweet entry, name, client } rescue logger.error "#{$!}\n#{$@.join("\n")}"
    end
  end

  desc 'continuously', 'Sync all new feeds from Ruby China to Twitter Continuously'
  def continuously
    invoke :all
    loop do
      sleep 3.minutes
      feeds_clients.each do |name, feed_client|
        feed = feed_client[:feed]
        client = feed_client[:client]
        begin
          log_timestamp
          Timeout::timeout(2.minutes) do
            feed = update_feed(feed)
            feed.new_entries.reverse.each { |entry| tweet(entry, name, client) } if feed.respond_to?(:updated?) && feed.updated?
          end
        rescue
          logger.error "#{$!}\n#{$@.join("\n")}"
        end
      end
    end
  end

  private
    def tweet entry, name, client
      return if has_sent_before?(name, entry)
      tweet = build_tweet(entry)
      retry_count = 0
      begin
        retry_count += 1
        client.update tweet
        touch_timestamp name, entry
        log_tweet name, tweet
      rescue
        retry if retry_count < 3
        log_lost name, tweet
      end
    end

    def update_feed feed
      Feedzirra::Feed.update feed
    end

    def logger
      @logger ||= Logger.new log_file('status.log')
    end

    def log_tweet(name, tweet)
      logger.info "Feed: #{name}"
      logger.info "Time: #{Time.now}"
      logger.info "Tweet: #{tweet}"
      logger.info ''
    end

    def build_tweet(entry)
      if entry.title.size > TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1
        entry.title[(TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1 - 3)..-1] = '...'
      end
      "#{entry.title} #{entry.url}"
    end

    def log_timestamp
      File.write log_timestamp_path, Time.now.to_s
    end

    def log_timestamp_path
      var_file('time')
    end

    def touch_timestamp name, entry
      @last_timestamp ||= {}
      @last_timestamp[name] = entry.published.to_i
      File.write last_timestamp_path(name), entry.published.to_i
    end

    def log_lost name, tweet
      lost_file = lost_file_path name
      logger.error "Failed to tweet '#{tweet}' for #{name}, reason: #{$!}, have log it into #{lost_file}"
      File.write lost_file, tweet
    end

    def has_sent_before? name, entry
      @last_timestamp ||= {}
      return false unless @last_timestamp[name] || File.exists?(last_timestamp_path(name))
      entry_published_time = entry.published.to_i

      last_entry_time = @last_timestamp[name] || File.read(last_timestamp_path(name)).to_i
      entry_published_time <= last_entry_time
    end

    def root_dir
      @_root_dir ||= File.expand_path(File.dirname(__FILE__))
    end

    def log_file(filename)
      File.join(root_dir, 'log', filename)
    end

    def config_file(filename)
      File.join(root_dir, 'config', filename)
    end

    def var_file(filename)
      File.join(root_dir, 'var', filename)
    end

    def lost_file(filename)
      File.join(root_dir, 'lost', filename)
    end

    def feeds_clients
      @_feeds_clients ||= begin
        Hash[feeds_info.map {|name, info|
          start_from = DateTime.parse(info['start_from']).to_time if info['start_from']
          feed = build_feed info['feed']
          client_info = info.slice('consumer_key', 'consumer_secret', 'oauth_token', 'oauth_token_secret').symbolize_keys
          [name, {feed: feed, client: Twitter::Client.new(client_info), start_from: start_from}]
        }]
      end
    end

    def build_feed source
      Feedzirra::Feed.fetch_and_parse source,
        on_success: ->(url, feed){
          logger.info "#{Time.now}: Fetch & Parse #{url} ..."
        },
        on_failure: ->(url, code, header, body){
          logger.error "#{Time.now}: Failed to Fetch & Parse #{url}\nError code: #{code}\nError header: #{header}\nError body: #{body}"
          exit 1
        }
    end

    def filter_feed(feed, since)
      feed.entries = feed.entries.select {|entry| entry.published > since } if since
      feed
    end

    def feeds_info
      @_feeds_info ||= begin
        if File.exists? config_file('feeds.yml')
          YAML.load_file config_file('feeds.yml')
        else
          raise LoadError.new '"feeds.yml" not found, please copy feeds.yml.example to feeds.yml and put all your feeds to it!'
        end
      end
    end

    def lost_file_path name
      name = "#{Time.now.to_f.to_s.sub('.', '')}-#{name}.tweet"
      lost_file(name)
    end

    def last_timestamp_path name
      @_last_timestamp_paths ||= Hash.new {|h, name| h[name] = var_file("#{name}.last") }
      @_last_timestamp_paths[name]
    end
end
