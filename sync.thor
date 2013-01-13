require 'thor'
require 'feedzirra'
require 'twitter'
require 'logger'

TWEET_MAX_LENGTH = 140
SHORT_URL_LENGTH = 23

class Sync < Thor
  desc 'all', 'Sync all new feeds from Ruby China to Twitter'
  def all
    feed.entries.reverse.each do |entry|
      next if has_sent_before?(entry)
      t = tweet(entry) 
      retry_count = 0
      begin
        retry_count += 1
        twitter.update t
        touch_timestamp(entry)
        logger.info t
      rescue
        retry if retry_count < 3
        log_lost t
      end
    end
  end

  private
    def feed
      @@feed ||= Feedzirra::Feed.fetch_and_parse 'http://ruby-china.org/topics/feed',
                    on_success: ->(url, feed){
                      logger.info "Fetch & Parse #{url} ..."
                    },
                    on_failure: ->(url, code, header, body){
                      logger.error "Failed to Fetch & Parse #{url}\nError code: #{code}\nError header: #{header}\nError body: #{body}"
                      exit 1
                    }
    end

    def twitter
      @@twitter ||= Twitter::Client.new(client_info)
    end

    def client_info
      @@client_info ||= YAML.load_file(config_file('key.yml')).symbolize_keys
    end

    def logger
      @@logger ||= Logger.new(log_file('ruby-china-twitter-notifier.log'))
    end

    def tweet(entry)
      if entry.title.size > TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1
        entry.title[(TWEET_MAX_LENGTH - SHORT_URL_LENGTH - 1 - 3)..-1] = '...'
      end
      "#{entry.title} #{entry.url}"
    end

    def touch_timestamp(entry)
      File.write last_timestamp_path, entry.published.to_i
    end

    def log_lost(t)
      lost_file = lost_file_path
      logger.error "Failed to tweet '#{t}', reason: #{$!}, have log it into #{lost_file}"
      File.write lost_file, t
    end

    def has_sent_before?(entry)
      return false unless File.exists?(last_timestamp_path)
      entry_published_time = entry.published.to_i
      last_entry_time = File.read(last_timestamp_path).to_i
      entry_published_time <= last_entry_time
    end

    def root_dir
      @@root_dir ||= File.expand_path(File.dirname(__FILE__))
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

    def lost_file_path
      name = Time.now.to_f.to_s.sub('.', '') + '.tweet'
      lost_file(name)
    end

    def last_timestamp_path
      @@last_timestamp_path ||= var_file('last')
    end
end
