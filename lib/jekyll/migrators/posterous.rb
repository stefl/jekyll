require 'rubygems'
require 'jekyll'
require 'fileutils'
require 'net/http'
require 'uri'
require "json"

# ruby -r './lib/jekyll/migrators/posterous.rb' -e 'Jekyll::Posterous.process(email, pass, api_key, blog)'

module Jekyll
  module Posterous
    def self.fetch(uri_str, limit = 10)
      # You should choose better exception.
      raise ArgumentError, 'Stuck in a redirect loop. Please double check your email and password' if limit == 0

      response = nil
      Net::HTTP.start('posterous.com') do |http|
        req = Net::HTTP::Get.new(uri_str)
        req.basic_auth @email, @pass
        response = http.request(req)
      end

      case response
        when Net::HTTPSuccess     then response
        when Net::HTTPRedirection then fetch(response['location'], limit - 1)
        else response.error!
      end
    end
    
    def self.download_image(u)
      path = 'images/%s' % u.split('/')[-1]
      url = URI.parse(u)
      found = false 
      until found 
        host, port = url.host, url.port if url.host && url.port 
        query = url.query ? url.query : ""
        req = Net::HTTP::Get.new(url.path + '?' + query)
        res = Net::HTTP.start(host, port) {|http|  http.request(req) } 
        res.header['location'] ? url = URI.parse(res.header['location']) : found = true 
      end 
      open(path, "wb") do |file|
        file.write(res.body)
      end
      path
    end

    def self.process(email, pass, api_token, blog = 'primary')
      @email, @pass, @api_token = email, pass, api_token
      FileUtils.mkdir_p "_posts"
      FileUtils.mkdir_p "_images"

      posts = JSON.parse(self.fetch("/api/v2/users/me/sites/#{blog}/posts?api_token=#{@api_token}").body)
      page = 1

      while posts.any?
        posts.each do |post|
          title = post["title"]
          slug = title.gsub(/[^[:alnum:]]+/, '-').downcase
          date = Date.parse(post["display_date"])
          content = post["body_html"]
          published = !post["is_private"]
          name = "%02d-%02d-%02d-%s.html" % [date.year, date.month, date.day, slug]

          # Get the relevant fields as a hash, delete empty fields and convert
          # to YAML for the header
          data = {
             'layout' => 'post',
             'title' => title.to_s,
             'published' => published
           }.delete_if { |k,v| v.nil? || v == ''}.to_yaml
  
          puts post["media"].inspect
          if post["media"] && post["media"]['images']
            post["media"]['images'].each do |img|
              path = download_image(img['full']['url'])
              tag = "<img src=\"/%s\" alt=\"%s\" />" % [path, img['full']['caption']]
              puts tag
              begin
                content[/\[\[posterous-content:[^\]]*\]\]/] = tag
              rescue IndexError
                puts "weird stuff happening"
              end
            end
          end

          File.open("_posts/#{name}", "w") do |f|
            f.puts data
            f.puts "---"
            f.puts content
          end
        end

        page += 1
        posts = JSON.parse(self.fetch("/api/v2/users/me/sites/#{blog}/posts?api_token=#{@api_token}&page=#{page}").body)
      end
    end
  end
end
