require 'rubygems'
require 'mechanize'

class String
  def chop_first_char
    self[1..-1]
  end
end

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
    sales_report_page = rifftrax_login(sales_report_page) if sales_report_page.search(SALES_HEADING).empty?

    product_list_page = agent.get @product_list_url
    # Iterate through product <TD> elements
    video_sample_urls = product_list_page.search(PRODUCT_TDS).inject([]) do |list,td|
      product_edit_url = "#{BASE_RT_URL}/node/#{td.text}/edit"
      @logger.debug "product_edit_url = #{product_edit_url}"
      product_edit_page = agent.get product_edit_url
      video_sample_url = product_edit_page.search(VIDEO_SAMPLE_EDIT_FIELD).first.get_attribute('value')
      list << /v=(.+)/.match(video_sample_url)[1]
    end

    # Iterate though product <TR> elements
    sales_report_page.search('//tbody/tr').inject({}) do |hash, product_row|
      ustats = get_youtube_stats agent, video_sample_urls.shift

      a = product_row.search('td/a').first
      title = a.text
      href = a.get_attribute('href').chop_first_char # leading '/'
      @logger.debug "title = #{title}"
      @logger.debug "href = #{href}"

      # Now to get our rankings
      iriffs_page = agent.get @iriffs_url
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
    page.search("//div[@class='panel-pane'][not(@id)]//div[@class='top-five']//a[@href='#{href}']").text.match(rank)[0] rescue 'none'
  end

  def top_50_rank(page, product_href)
    # No digit embedded in text here, have to iterate though to find out our rank number
    # Also the hrefs have the leading '/' here so we have to look for it.
    iriffs_page.search('div[@id="iriffs-top-50"]//li//a').map{|e| e.get_attribute 'href'}.index("/#{href}") + 1 rescue 'none'
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
    @logger.info "Trying login to rifftrax.com"
    form = page.forms[1]
    form['name'] = 'username'
    form['pass'] = 'password'
    form.click_button
  end  
end
