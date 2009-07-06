require 'optparse'
require 'pp'
require 'chatbot'
require 'rifftrax_account'

options = {
  :channel => 'test',
  :full => 'iRiff report bot',
  :nick => 'riffbot',
  :port => '6667',
  :server => 'irc.freenode.net',
  :top_50 => false,
  :interval => 5
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-c', '--channel NAME', 'Specify IRC channel to /join.') {|c| options[:channel] = c}
  opts.on('-f', '--full-name NICK', 'Specify the bot\'s IRC full name.') {|n| options[:full] = n}
  opts.on('-n', '--nick NICK', 'Specify the bot\'s IRC nick.') {|n| options[:nick] = n}
  opts.on('-s', '--server HOST', 'Specify IRC server hostname.') {|h| options[:server] = h}
  opts.on('-p', '--port NUMBER', 'Specify IRC port number.') {|p| options[:port] = p}
  opts.on('-t', '--[no-]top_50', 'Report top 50 rankings (they twitch a lot).') {options[:top_50] = true}
  opts.on('-i', '--interval', 'Number of minutes to sleep between checks') do |interval|
    fail "Interval minimum is 5 minutes." unless interval >= 5
    options[:interval] = interval
  end

  opts.on_tail('-h', '--help', 'Display this screen') {puts opts; exit}
end

optparse.parse!

class Hash
  # This is used to tell when info has changed between checks
  def diff(h2)
    self.dup.delete_if {|k, v| h2[k] == v}.merge(h2.dup.delete_if {|k, v| self.has_key?(k)})
  end
end

class Riffbot < Chatbot
  USER_ID = 25482 

  def initialize(options)
    super options[:nick], options[:server], options[:port], options[:full]
    @options = options

    # We keep the latest stats in this Hash.
    @riff_stats = {}

    @logger.level = Logger::DEBUG
    @account = RifftraxAccount.new :user => USER_ID, :logger => @logger

    # The channel to join.
    add_room('#' + options[:channel])

    # Here you can modify the trigger phrase
    add_actions({
      /^(riff.*report|\.)$/ => lambda {|e,m| send_report e, @riff_stats},
      /^(riff.*top50|\.50)$/ => lambda {|e,m| options[:top_50] = !options[:top_50]; reply e, "Top 50 announcment mode: #{options[:top_50] ? 'active' : 'passive'}."},
      /^(riff.*help|\.\?)$/ => lambda {|e,m| print_legend e}
    })
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

          changed_riffs.each{|s| s.delete :iriff} unless @options[:top_50]

          send_report event, changed_riffs
          @riff_stats = new_stats

          sleep interval * 60
        rescue 
          @logger.error $!
        end
      end
    end
  end

  def send_report(event, riff_stats)
    start_polling_thread event unless @polling_thread

    riff_stats.each do |title, stats|
      # get the list of names that actually have values
      names = RifftraxAccount::STAT_NAMES.select {|x| stats[x.to_sym]}

      reply event, report_string(title, stats, names) unless names.empty?
    end
  end

  def report_string(title, stats, names)
    @logger.debug title.pretty_inspect
    @logger.debug stats.pretty_inspect
    @logger.debug names.pretty_inspect

    "#{title} -> " + names.map {|n| "#{n}:#{stats[n.to_sym]}"}.join(' ')
  end

  def print_legend(event)
    RifftraxAccount::STAT_NAMES.each do |name|
      reply event, name
    end
  end
end

Riffbot.new(options).start
