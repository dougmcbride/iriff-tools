require 'rubygems'
require 'pp'
require 'chatbot'
require 'rifftrax_account'

class Hash
  # This is used to tell when info has changed between checks
  def diff(h2)
    self.dup.delete_if {|k, v| h2[k] == v}.merge(h2.dup.delete_if {|k, v| self.has_key?(k)})
  end
end

class Riffbot < Chatbot
  USER_ID = 25482 

  def initialize(*args)
    super

    # We keep the latest stats in this Hash.
    @riff_stats = {}

    @logger.level = Logger::DEBUG
    @account = RifftraxAccount.new :user => USER_ID, :logger => @logger

    # The channel to join.
    add_room "##{ARGV[0] || 'test'}"

    # Here you can modify the trigger phrase
    add_actions({ /riff.*report|^\.$/ => lambda {|e,m| send_report e, @riff_stats} })
  end

  def start_polling_thread(event)
    @polling_thread = Thread.new do 
      loop do
        begin
          new_stats = @account.get_iriff_stats

          # Here we make new Hashes which are the diffs between
          # What we have stored and what we just got, to see what we
          # need to announce.
          changed_riffs = new_stats.keys.inject({}) do |hash, title|
            hash[title] = new_stats[title].diff(@riff_stats[title] || {})
            hash
          end

          @logger.debug changed_riffs.pretty_inspect

          send_report event, changed_riffs
          @riff_stats = new_stats

          sleep 300  # Be nice to rifftrax.com by not decreasing this!
        rescue 
          @logger.error $!
        end
      end
    end
  end

  def send_report(event, riff_stats)
    start_polling_thread event unless @polling_thread

    riff_stats.each do |title, stats|
      names = STAT_NAMES.select {|x| stats[x.to_sym]}
      reply event, report_string(title, stats, names) unless names.empty?
    end
  end

  def report_string(title, stats, names)
    @logger.debug title.pretty_inspect
    @logger.debug stats.pretty_inspect
    @logger.debug names.pretty_inspect

    "#{title} -> " + names.map {|n| "#{n}:#{stats[n.to_sym]}"}.join(' ')
  end
end

Riffbot.new("ruffbot", "irc.sneakyfrog.com", "2665", "RiffBot").start
