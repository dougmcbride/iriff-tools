require 'chatbot'
require 'rubygems'
require 'mechanize'
require 'pp'

class Hash
  def diff(h2)
    self.dup.delete_if { |k, v| h2[k] == v }.merge(h2.dup.delete_if { |k, v| self.has_key?(k) })
  end
end

class Riffbot < Chatbot
  STAT_NAMES = %w(views sold $ yt rt->yt seller short iriff)

  def initialize(*args)
    super

    @riff_stats = {}
    @logger.level = Logger::DEBUG

    add_room "##{ARGV[0] || 'test'}"

    add_actions({ /riff.*report|^\.$/ => lambda {|e,m| send_report e, @riff_stats} })
  end

  def create_agent
    @agent = WWW::Mechanize.new {|a| a.log = @logger}
  end

  def start_polling_thread(event)
    #@polling_thread.kill if @polling_thread

    @polling_thread = Thread.new do 
      loop do
        begin
          create_agent
          new_stats = get_stats @agent

          changed_riffs = new_stats.keys.inject({}) do |hash, title|
            hash[title] = new_stats[title].diff(@riff_stats[title] || {})
            hash
          end

          @logger.debug changed_riffs.pretty_inspect

          send_report event, changed_riffs
          @riff_stats = new_stats

          sleep 100
        rescue 
          @logger.error $!
          #reply event, "Ugh: #{$!}"
          create_agent
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

  def get_stats(agent)
    sales_report_page = agent.get 'http://www.rifftrax.com/rifftrax/register?destination=user%2F25482%2Fselling%2Freports%2Fproduct'
    puts "sales_report_page=#{sales_report_page}"

    sales_report_page = rifftrax_login(sales_report_page) if sales_report_page.search("//h1[. ='Product Sales']").empty?
    @logger.info "Logged in to rifftrax.com"

    product_list_page = agent.get 'http://www.rifftrax.com/user/25482/selling'
    video_sample_urls = product_list_page.search("//div[@id='content-area']/table/tbody/tr/td[1]").inject([]) do |list,td|
      @logger.debug "http://www.rifftrax.com/node/#{td.text}/edit"
      edit_page = agent.get "http://www.rifftrax.com/node/#{td.text}/edit"
      edit_page.search("//input[@id='edit-field-sample-0-value']").first.get_attribute('value') =~ /v=(.+)/
      fail "Couldn't parse video token" unless $1
      list << $1
    end

    sales_report_page.search('//tbody/tr').inject({}) do |hash,tr|
      ustats = get_youtube_stats @agent, video_sample_urls.shift

      a = tr.search('td/a').first
      title = a.text
      href = a.get_attribute('href')[1..255]
      @logger.debug "title = #{title}"
      @logger.debug "href = #{href}"

      iriffs_page = agent.get 'http://www.rifftrax.com/iriffs'
      rank = /^(\d+)/
      top_seller_rank = iriffs_page.search("//div[@id='iriffs-top-sellers']//a[@href='#{href}']").text.match(rank)[0] rescue 'FUCK'
      top_shorts_rank = iriffs_page.search("//div[@class='panel-pane'][not(@id)]//div[@class='top-five']//a[@href='#{href}']").text.match(rank)[0] rescue 'FUCK'
      top_50_rank = iriffs_page.search('div[@id="iriffs-top-50"]//li//a').map{|e| e.get_attribute 'href'}.index("/#{href}") + 1 rescue 'FUCK'

      hash[title] = ustats.merge \
        :sold  => tr.search('td/strong').first.text,
        :'$' => tr.search('td/strong').last.text[1..255],
        :views => tr.search('td')[2].text,
	:seller => "##{top_seller_rank}",
	:short => "##{top_shorts_rank}",
	:iriff => "##{top_50_rank}"

      hash
    end
  end

  def get_youtube_stats(agent, video_token)
    p1 = agent.get "http://www.youtube.com/watch?v=#{video_token}"
    p2 = agent.get "http://www.youtube.com/watch_ajax?v=#{video_token}&action_get_statistics_and_data=1&l=EN"
    x1 = Nokogiri::XML p2.body
    h1 = x1.search('html_content').first.text
    p3 = Nokogiri::HTML h1 

    urtrefs = p3.search("//div[@class='watch-ref-url']/a[contains(@href,'rifftrax')]/../preceding-sibling::div[1]").inject(0) do |count, element|
      count + element.text.strip.gsub(/,/,'').to_i
    end

    {
      :title => p1.search('h1').first.text,
      :yt => p1.search("//span[@id='watch-view-count']").first.text,
      :'rt->yt' => urtrefs
    }
  end


  def rifftrax_login(page)
    @logger.info "Logging in to rifftrax.com"
    form = page.forms[1]
    form['name'] = 'username'
    form['pass'] = 'password'
    form.click_button
  end  

  private

  def report_string(title, stats, names)
    @logger.debug title.pretty_inspect
    @logger.debug stats.pretty_inspect
    @logger.debug names.pretty_inspect

    "#{title} -> " + names.map {|n| "#{n}:#{stats[n.to_sym]}"}.join(' ')
  end
end

Riffbot.new("ruffbot", "irc.sneakyfrog.com", "2665", "RiffBot").start
