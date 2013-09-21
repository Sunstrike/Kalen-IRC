# Kalen build status bot

require 'daemons'

Daemons.run_proc('kalen.rb') do
  require 'cinch'
  require_relative 'config.rb'
  require 'cinch/plugins/identify'
  require 'sinatra/base'
  require 'ipaddr'
  require 'multi_json'
  require 'net/http'

# Listener

  class POSTListener
    include Cinch::Plugin

    def initialize(bot)
      super bot

      t = Thread.new(self) { |callback|
        SinatraServer.set :controller, callback
        SinatraServer.set :port, config[:port]
        SinatraServer.run!
      }
    end

    def report(data)
      begin
        channel = Channel(config[:channel])
        project = data['project']
        devchannel = data['channel']
        version = data['version']

        url = data['url']
        puts channel.inspect
        channel.msg "#{project}: #{devchannel} build #{version} pushed to Tanis: #{url}"
        reportChangesForBuild(data)
      rescue Exception => e
        warn "Failed to send message: #{e.message}"
      end
    end

    def handle(req, payload)
      ret = 200
      begin
        data = MultiJson.decode payload
        info "Got POST from build endpoint: #{data.inspect}"
        report(data)
      end
      ret
    end

    def reportChangesForBuild(data)
      channel = Channel(config[:channel])
      msgs = getChangesFromREST(data['buildkey'])
      msgs.each do |m|
        channel.msg m
      end
    end

    def getChangesFromREST(buildkey)
      uri = URI("#{config[:api]}/result/#{buildkey}.json?expand=changes.change")
      req = Net::HTTP::Get.new(uri)
      req.basic_auth config[:user], config[:password]
      res = Net::HTTP.start(uri.hostname, uri.port, :use_ssl => uri.scheme == 'https', :verify_mode => OpenSSL::SSL::VERIFY_NONE) do |http|
        http.request(req)
      end
      if res.is_a?(Net::HTTPSuccess)
        json = MultiJson.decode res.body
        puts json.inspect

        puts json['changes']
        if json['changes']['size'] <= 0
          matches = /.+>(.+)<\/a>/.match json['buildReason']
          unless matches == nil
            return ["This build appears to be a manual run by #{matches[1]}."]
          else
            return []
          end
        else
          out = []
          json['changes']['change'].each do |change|
            puts change.inspect
            out.push("[#{change['changesetId'][0..5]}] #{change['comment'].chomp}")
          end
          return out
        end
      end
    end

  end

  class SinatraServer < Sinatra::Base
    set :port, 9090
    set :environment, :production
    server.delete 'webrick'

    post '/build' do
      settings.controller.handle(request, params[:payload])
    end
  end

# END Listener

  plugins = [Cinch::Plugins::Identify, POSTListener]

  bot = Cinch::Bot.new do
    configure do |c|
      c.server = SERVER
      c.port = PORT
      c.nick = NICK
      c.user = NICK
      c.realname = "Kalen::Cinch Status Bot"
      c.channels = [CHANNEL]
      c.plugins.plugins = plugins
      c.messages_per_second = 5
      c.local_host = "0.0.0.0"
      if NS_ENABLED
        c.plugins.options[Cinch::Plugins::Identify] = {
            :username => NICK,
            :password => NS_PASSWORD,
            :type => :nickserv,
        }
      end
      c.plugins.options[POSTListener] = {
          :port => POST_PORT,
          :channel => CHANNEL,
          :api => REST_API,
          :user => REST_USERNAME,
          :password => REST_PASSWORD
      }
    end
  end

  bot.start
end
