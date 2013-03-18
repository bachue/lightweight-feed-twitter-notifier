require 'thor'
require 'feedzirra'
require 'twitter'
require 'logger'
require 'active_support/all'

TWEET_MAX_LENGTH = 140
SHORT_URL_LENGTH = 23

class Sync < Thor
  desc 'all', 'Sync all new feeds from Ruby China to Twitter'
  def all
    feed.entries.reverse.each { |entry| twitter(entry) } rescue logger.error "#{$!}\n#{$@.join("\n")}"
  end

  desc 'continuously', 'Sync all new feeds from Ruby China to Twitter Continuously'
  def continuously
    invoke :all
    loop do
      sleep 3.minutes
      begin
        log_timestamp
        feed = update_feed
        feed.new_entries.reverse.each { |entry| twitter(entry) } if feed.respond_to?(:updated?) && feed.updated?
      rescue
        logger.error "#{$!}\n#{$@.join("\n")}"
      end
    end
  end

  private
    def twitter(entry)
      return if has_sent_before?(entry)
      tweet = tweet(entry)
      retry_count = 0
      begin
        retry_count += 1
        client.update tweet
        touch_timestamp(entry)
        logger.info tweet
      rescue
        retry if retry_count < 3
        log_lost tweet
      end
    end

    def feed
      @feed ||= Feedzirra::Feed.fetch_and_parse feed_source,
                    on_success: ->(url, feed){
                      logger.info "Fetch & Parse #{url} ..."
                    },
                    on_failure: ->(url, code, header, body){
                      logger.error "Failed to Fetch & Parse #{url}\nError code: #{code}\nError header: #{header}\nError body: #{body}"
                      exit 1
                    }
    end

    def update_feed
      Feedzirra::Feed.update(feed)
    end

    def client
      @twitter_client ||= Twitter::Client.new(client_info)
    end

    def client_info
      @client_info ||= YAML.load_file(config_file('key.yml')).symbolize_keys
    end

    def logger
      @logger ||= Logger.new(log_file('ruby-china-twitter-notifier.log'))
    end

    def tweet(entry)
      if entry.title.size > TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1
        entry.title[(TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1 - 3)..-1] = '...'
      end
      "#{entry.title} #{entry.url}"
    end

    def log_timestamp
      File.write log_timestamp_path, Time.now
    end

    def log_timestamp_path
      var_file('time')
    end

    def touch_timestamp(entry)
      @last_timestamp = entry.published.to_i
      File.write last_timestamp_path, entry.published.to_i
    end

    def log_lost(tweet)
      lost_file = lost_file_path
      logger.error "Failed to tweet '#{tweet}', reason: #{$!}, have log it into #{lost_file}"
      File.write lost_file, tweet
    end

    def has_sent_before?(entry)
      return false unless @last_timestamp || File.exists?(last_timestamp_path)
      entry_published_time = entry.published.to_i
      last_entry_time = @last_timestamp || File.read(last_timestamp_path).to_i
      entry_published_time <= last_entry_time
    end

    def root_dir
      @root_dir ||= File.expand_path(File.dirname(__FILE__))
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

    def feed_source
      if File.exists? config_file('test_feed')
        File.read config_file('test_feed')
      else
        'http://ruby-china.org/topics/feed'
      end
    end

    def lost_file_path
      name = Time.now.to_f.to_s.sub('.', '') + '.tweet'
      lost_file(name)
    end

    def last_timestamp_path
      @last_timestamp_path ||= var_file('last')
    end
end
