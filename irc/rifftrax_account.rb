require 'rubygems'
require 'mechanize'

class String
  def chop_first_char
    self[1..-1]
  end
end

class RifftraxAccount
  BASE_RT_URL = 'http://www.rifftrax.com'
  LOGIN_URL = "https://www.rifftrax.com/rifftrax/register?destination=content"
  VIDEO_SAMPLE_EDIT_FIELD = "//input[@id='edit-field-sample-0-value']"
  PRODUCT_TDS = "//div[@id='content-area']/table/tbody/tr/td[1]"
  SALES_HEADING = "//h1[. ='Product Sales']"
  MY_IRIFFS_LINK = "//a[. ='My iRiffs']"

  STAT_NAMES = %w(views sold $ yt rt->yt seller short iriff)
  LEGEND = {
    :views => 'Number of views of product page',
    :sold => 'Number of sales for product',
    :"$" => 'Total revenue from product',
    :yt => 'Number of views of youtube sample video',
    :"rt->yt" => 'Number of views embedded on RT.com (sample viewer on product page)',
    :seller => 'Rank in last week\'s top seller list',
    :short => 'Rank in last week\'s top shorts list',
    :iriff => 'Rank in iRiff Top 50 list'
  }

  def self.legend_for(key)
    LEGEND[key.to_sym]
  end

  def initialize(options)
    @options = options
    @logger = options[:logger]
    @iriffs_url = "#{BASE_RT_URL}/iriffs"
  end

  def create_agent
    WWW::Mechanize.new {|a| a.log = @logger; a.keep_alive = false}
  end

  def get_iriff_stats
    agent = create_agent
    main_page = rifftrax_login agent

    product_list_url = main_page.search(MY_IRIFFS_LINK).first.get_attribute('href')
    product_list_page = agent.get product_list_url

    # Iterate through product <TD> elements
    video_sample_urls = product_list_page.search(PRODUCT_TDS).inject([]) do |list,td|
      product_edit_url = "#{BASE_RT_URL}/node/#{td.text}/edit"
      @logger.debug "product_edit_url = #{product_edit_url}"
      product_edit_page = agent.get product_edit_url
      video_sample_url = product_edit_page.search(VIDEO_SAMPLE_EDIT_FIELD).first.get_attribute('value')
      list << /v=(.+)/.match(video_sample_url)[1]
    end

    iriffs_page = agent.get @iriffs_url

    sales_report_url = product_list_url + '/reports/product'
    sales_report_page = agent.get sales_report_url
    # Iterate though product <TR> elements
    sales_report_page.search('//tbody/tr').inject({}) do |hash, product_row|
      ustats = get_youtube_stats agent, video_sample_urls.shift rescue {}

      a = product_row.search('td/a').first
      title = a.text
      href = a.get_attribute('href').chop_first_char # leading '/'
      @logger.info "title = #{title}"
      @logger.info "href = #{href}"

      # Now extract our rankings
      top_seller_rank = top_seller_rank iriffs_page, href
      top_shorts_rank = top_shorts_rank iriffs_page, href
      top_50_rank = top_50_rank iriffs_page, href

      hash[title] = ustats.merge \
        :sold  => product_row.search('td/strong').first.text,
        :'$' => product_row.search('td/strong').last.text.chop_first_char,  # '$'
        :views => product_row.search('td')[2].text,
        :seller => "##{top_seller_rank}",
        :short => "##{top_shorts_rank}",
        :iriff => "##{top_50_rank}"

      hash
    end
  end

  def top_seller_rank(page, product_href)
    rank = /^(\d+)/
    page.search("//div[@id='iriffs-top-sellers']//a[@href='#{product_href}']").text.match(rank)[0] rescue 'none'
  end

  def top_shorts_rank(page, product_href)
    rank = /^(\d+)/
    page.search("//div[@class='panel-pane'][not(@id)]//div[@class='top-five']//a[@href='#{product_href}']").text.match(rank)[0] rescue 'none'
  end

  def top_50_rank(page, product_href)
    # No digit embedded in text here, have to iterate though to find out our rank number
    # Also the hrefs have the leading '/' here so we have to look for it.
    page.search("//h2[. ='Top 50 iRiffs']/following-sibling::div[@class=\"content\"]//li//a").map{|e| e.get_attribute 'href'}.index("/#{product_href}") + 1 rescue 'none'
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

  def rifftrax_login(agent)
    @logger.info "Trying login to rifftrax.com"
    login_page = agent.get LOGIN_URL
    form = login_page.forms[1]
    form['name'] = @options[:username]
    form['pass'] = @options[:password]
    form.click_button
  end  
end
