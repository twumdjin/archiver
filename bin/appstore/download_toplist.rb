#!/usr/bin/env ruby

require 'faraday'
require 'faraday_middleware'
require 'fileutils'
require 'json'
require 'open-uri'
require 'zlib'

# Define download class
# Probably should live elsewhere...
class HttpClient
  def get(url)
    # Default to something bad
    code = 0
    begin
      conn = ::Faraday.new(url) do |c|
        c.use ::FaradayMiddleware::FollowRedirects
        c.adapter ::Faraday.default_adapter
      end
      conn.headers = {
        'User-Agent' => 'Mozilla/5.0 (X11; Ubuntu; Linux x86_64; rv:25.0) Gecko/20100101 Firefox/25.0',
        'Accept' => 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language' => 'en-US,en;q=0.5',
        'Accept-Encoding' => 'gzip, deflate',
        'Connection' => 'keep-alive',
      }
      response = conn.get
      if response.respond_to?(:status)
        code = response.status.to_i
      end
    rescue OpenURI::HTTPRedirect => e
      return nil, 302, response
    rescue EOFError, OpenURI::HTTPError, RuntimeError => e
      puts("Failed to execute GET request to #{url}. Error was #{e.class} #{e.message}")
      code = 0
    end
    if code < 200 || code > 300
      puts "response code was #{code}"
      puts "response was #{response.body}" if response
      data = nil
    elsif response.headers['Content-Encoding'] == 'gzip' then
      begin
        data = Zlib::GzipReader.new(StringIO.new(response.body)).read
      rescue Zlib::DataError => e
        data = nil
        puts("Error unzipping data from #{url}. Error was #{e.class} #{e.message}")
      end
    else
      data = response.body
    end
    data
  end
  
  def save_remote(url, file_name)
    dirname = File.dirname(file_name)
    FileUtils.mkdir_p(dirname) unless File.directory?(dirname)
    if File.exist?(file_name)
      puts "Skipping existing file: #{file_name}"
      return
    end
    data = self.get(url)
    raise "Failed to save resource at #{url} to file #{file_name}" unless data
    File.open(file_name, 'w') do |f|
      f.write(data)
    end
    puts "Successfully saved file: #{file_name}"
  end
end

# Enumerate endpoints for rss
DEFAULT_LIMIT = 200
COUNTRIES = %w(us gb au ca hk kr cn jp in fr)
TOPLISTS = %w(topfreeapplications toppaidapplications topgrossingapplications topfreeipadapplications toppaidipadapplications topgrossingipadapplications newapplications newfreeapplications newpaidapplications)
URL_FORMAT = 'https://itunes.apple.com/%{country_code}/rss/%{list_name}/limit=%{limit}/json'
FILE_FORMAT = '/import/appstore/toplist/%{list_name}/%{date}/%{country_code}.json'

# Format date string
date = Time.now.strftime('%Y/%m/%d')
# Iterate over endpoints and fetch rss for today
http_client = HttpClient.new
write_count = 0
COUNTRIES.each do |country_code|
  TOPLISTS.each do |list_name|
    params = {country_code: country_code, list_name: list_name, date: date, limit: DEFAULT_LIMIT}
    url = URL_FORMAT % params
    file_name = FILE_FORMAT % params
    http_client.save_remote(url, file_name)
    write_count += 1
  end
end

puts "Written #{write_count} files today"
