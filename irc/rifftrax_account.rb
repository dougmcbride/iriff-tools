require 'rubygems'
require 'mechanize'

class RifftraxAccount
  BASE_RT_URL = 'http://www.rifftrax.com'
  STAT_NAMES = %w(views sold $ yt rt->yt seller short iriff)
  VIDEO_SAMPLE_EDIT_FIELD = "//input[@id='edit-field-sample-0-value']"
  PRODUCT_TDS = "//div[@id='content-area']/table/tbody/tr/td[1]"
  SALES_HEADING = "//h1[. ='Product Sales']"

  def initialize(options)
    @user_id = options[:user]
    @logger = options[:logger]
    @sales_report_url = "#{BASE_RT_URL}/rifftrax/register?destination=user%2F#{@user_id}%2Fselling%2Freports%2Fproduct"
    @product_list_url = "#{BASE_RT_URL}/user/#{@user_id}/selling"
    @iriffs_url = "#{BASE_RT_URL}/iriffs"
  end

  def create_agent
    WWW::Mechanize.new {|a| a.log = @logger}
  end

  def get_iriff_stats
    agent = create_agent

    sales_report_page = agent.get @sales_report_url
    @logger.debug "sales_report_page=#{sales_report_page}"

    sales_report_page = rifftrax_login(sales_report_page) if sales_report_page.search(SALES_HEADING).empty?
    @logger.info "Logged in to rifftrax.com"

    product_list_page = agent.get @product_list_url
    video_sample_urls = product_list_page.search(PRODUCT_TDS).inject([]) do |list,td|
      @logger.debug "#{BASE_RT_URL}/node/#{td.text}/edit"
      edit_page = agent.get "#{BASE_RT_URL}/node/#{td.text}/edit"
      edit_page.search(VIDEO_SAMPLE_EDIT_FIELD).first.get_attribute('value') =~ /v=(.+)/
      fail "Couldn't parse video token" unless $1
      list << $1
    end

    sales_report_page.search('//tbody/tr').inject({}) do |hash,tr|
      ustats = get_youtube_stats agent, video_sample_urls.shift

      a = tr.search('td/a').first
      title = a.text
      href = a.get_attribute('href')[1..-1] # Chop off the first '/'
      @logger.debug "title = #{title}"
      @logger.debug "href = #{href}"

      iriffs_page = agent.get @iriffs_url
      rank = /^(\d+)/
      top_seller_rank = iriffs_page.search("//div[@id='iriffs-top-sellers']//a[@href='#{href}']").text.match(rank)[0] rescue 'none'
      top_shorts_rank = iriffs_page.search("//div[@class='panel-pane'][not(@id)]//div[@class='top-five']//a[@href='#{href}']").text.match(rank)[0] rescue 'none'
      top_50_rank = iriffs_page.search('div[@id="iriffs-top-50"]//li//a').map{|e| e.get_attribute 'href'}.index("/#{href}") + 1 rescue 'none'

      hash[title] = ustats.merge \
        :sold  => tr.search('td/strong').first.text,
        :'$' => tr.search('td/strong').last.text[1..-1],
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
end
