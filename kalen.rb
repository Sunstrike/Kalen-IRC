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
  require 'googl'

# Listener

  class POSTListener
    include Cinch::Plugin

    @@start_messages = ["\#@build@: On your marks, get set, build!",
                        "\#@build@: Building... with blocks.",
                        "\#@build@: Starting build. If it's broken, blame the person sitting next to me.",
                        "\#@build@: <press any key to build>"]
    @@success_messages = ["@project@ (@channel@): All your build @version@ are belong to @link@",
                          "@project@ (@channel@): I'MA FIRING MY LAZOR!!! @version@ @link@",
                          "@project@ (@channel@): Build @version@ completed. What else did you want? @link@",
                          "@project@ (@channel@): Build @version@: Buried treasure ahoy! Set sail for adventure! @link@",
                          "@project@ (@channel@): Build @version@: Arrr.... We got that ticking gator @link@",
                          "@project@ (@channel@): My little @version@, my little @link@",
                          "@project@ (@channel@): We've got high @version@, we've got high @link@",
                          "@project@ (@channel@): Build @version@ feels pretty good! @link@",
                          "@project@ (@channel@): Build @version@ has high hopes for the future. @link@",
                          "@project@ (@channel@): @link@. Oops, shouldn't that have been for @version@?",
                          "@project@ (@channel@): Build @version@. Heyo! @link@",
                          "@project@ (@channel@): Gardevoir is the best pokemon! Build @version@, @link@",
                          "@project@ (@channel@): We like a bit of Shinx too. Build @version@, @link@",
                          "@project@ (@channel@): Build @version@ would like to thank their mother, father, and the great cube in the sky. @link@",
                          "@project@ (@channel@): Prepare for the jarpocalypse! Build @version@, @link@",
                          "@project@ (@channel@): Build @version@, a developer's best friend. @link@",
                          "@project@ (@channel@): Once upon a time, there was a build @version@ that visited their grandma @link@",
                          "@project@ (@channel@): Build @version@ Press any key to start. Well, where's the any key? @link@",
                          "@project@ (@channel@): Build @version@ belongs to @link@. My precioussssss",
                          "@project@ (@channel@): I LIKE TO MOVE IT MOVE IT. Build @version@, @link@"]
    @@failure_messages = ["Build \#@build@ thought ice cream was better.",
                          "Build \#@build@ walked the plank.",
                          "Build \#@build@ fell off a cliff.",
                          "Build \#@build@ stubbed its toe.",
                          "Build \#@build@ walked the plank, yaarrr.",
                          "Build \#@build@ was assassinated by pudding.",
                          "Build \#@build@ has made a mess on the floor.",
                          "Build \#@build@ was playing on the tracks.",
                          "Build \#@build@ couldn't find the 'any' key.",
                          "Build \#@build@ fell into a smeltery. Head first.",
                          "Cleanup on aisle @build@..."]

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
        url = Googl.shorten(data['url']).short_url

        #channel.msg "#{project}: #{devchannel} build #{version} pushed to Tanis: #{url}"
        channel.msg @@success_messages.sample.gsub("@project@", project).gsub("@channel@", devchannel).gsub("@version@", version).gsub("@link@", url)
        reportChangesForBuild(data)
      rescue Exception => e
        warn "Failed to send message: #{e.message}"
      end
    end

    def report_start(data)
      begin
        channel = Channel(config[:channel])
        project = data['project']
        build = data['build']

        msg = @@start_messages.sample.gsub("@project@", project).gsub("@build@", build)
        channel.msg msg
      rescue Exception => e
        warn "Failed to send message: #{e.message}"
      end
    end

    def report_fail(data)
      begin
        channel = Channel(config[:channel])
        project = data['project']
        build = data['build']

        msg = @@failure_messages.sample.gsub("@project@", project).gsub("@build@", build)
        channel.msg msg
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

    def handle_start(req, payload)
      ret = 200
      begin
        data = MultiJson.decode payload
        info "Got POST from build-start endpoint: #{data.inspect}"
        report_start(data)
      end
      ret
    end

    def handle_fail(req, payload)
      ret = 200
      begin
        data = MultiJson.decode payload
        info "Got POST from build-fail endpoint: #{data.inspect}"
        report_fail(data)
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

    post '/build-start' do
      settings.controller.handle_start(request, params[:payload])
    end

    post '/build-fail' do
      settings.controller.handle_fail(request, params[:payload])
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
