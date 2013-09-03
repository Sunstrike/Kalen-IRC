# Kalen build status bot

require 'daemons'

Daemons.run_proc('kalen.rb') do
  require 'cinch'
  require_relative 'config.rb'
  require 'cinch/plugins/identify'
  require 'sinatra/base'
  require 'ipaddr'
  require 'multi_json'

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
      if NS_ENABLED
        c.plugins.options[Cinch::Plugins::Identify] = {
            :username => NICK,
            :password => NS_PASSWORD,
            :type => :nickserv,
        }
      end
      c.plugins.options[POSTListener] = {
          :port => POST_PORT,
          :channel => CHANNEL
      }
    end
  end

  bot.start
end
