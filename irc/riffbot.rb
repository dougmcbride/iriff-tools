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
  :interval => 5,
  :logging => :warn
}

optparse = OptionParser.new do |opts|
  opts.banner = "Usage: #{$0} [options]"

  opts.on('-u', '--username USERNAME', 'Specify rifftrax.com username.') {|options[:username]|}
  opts.on('-w', '--password PASSWORD', 'Specify rifftrax.com password.') {|options[:password]|}
  opts.on('-c', '--channel NAME', 'Specify IRC channel to /join.') {|options[:channel]|}
  opts.on('-f', '--full-name NICK', 'Specify the bot\'s IRC full name.') {|options[:full]|}
  opts.on('-n', '--nick NICK', 'Specify the bot\'s IRC nick.') {|options[:nick]|}
  opts.on('-s', '--server HOST', 'Specify IRC server hostname.') {|options[:server]|}
  opts.on('-p', '--port NUMBER', Integer, 'Specify IRC port number.') {|options[:port]|}
  opts.on('-t', '--top-50', 'Actively report top 50 rankings (they twitch a lot).') {|options[:top_50]|}
  opts.on('-l', '--logging LEVEL', [:debug, :info, :warn, :error, :fatal], 'Logging level (debug, info, warn, error, fatal)') {|options[:logging]|}

  opts.on('-i', '--interval MINUTES', Integer, 'Number of minutes to sleep between checks') do |interval|
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

    @logger.level = eval "Logger::#{options[:logging].to_s.upcase}"

    @account = RifftraxAccount.new \
      :user => USER_ID,
      :logger => @logger,
      :username => options[:username],
      :password => options[:password]

    # The channel to join.
    add_room('#' + options[:channel])

    # Here you can modify the trigger phrase
    add_actions({
      /^(riff.*report|\.)$/ => lambda {|e,m| send_report e, @riff_stats},
      /^(riff.*top50|\.50)$/ => lambda {|e,m| @options[:top_50] = !@options[:top_50]; reply e, "Top 50 announcment mode: #{@options[:top_50] ? 'active' : 'passive'}."},
      /^(?:riff.*interval|\.i) (\d+)$/ => lambda {|e,m|
        i = m[1].to_i
        if i > 4
          @options[:interval] = m[1].to_i
          reply e, "Sleep interval set to #{@options[:interval]} minutes."
        else
          reply e, "Sleep interval cannot be less than 5 minutes."
        end
      },
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

          @logger.info "changed_riffs = #{changed_riffs.pretty_inspect}"

          changed_riffs.each{|s| s.last.delete :iriff} unless @options[:top_50]

          send_report event, changed_riffs
          @riff_stats = new_stats

          sleep @options[:interval] * 60
        rescue 
          @logger.error $!
          exit 1
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
