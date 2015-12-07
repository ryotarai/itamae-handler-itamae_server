require "itamae/handler/base"
require "itamae/handler/itamae_server/version"

require "uri"
require "faraday"
require "socket"
require "json"

module Itamae
  module Handler
    class ItamaeServer < Base
      INTERVAL = 10

      def initialize(*)
        super
        @events = []
        start_thread
      end

      def event(type, payload = {})
        super
        payload = payload.merge(
          recipes: @recipes.dup,
          resources: @resources.dup,
          actions: @actions.dup,
        )
        @events << [type, payload]
      end

      private
      def conn
        @conn ||= Faraday.new(url: "#{url.scheme}://#{url.host}:#{url.port}") do |faraday|
          faraday.request :url_encoded
          faraday.adapter Faraday.default_adapter
        end
      end

      def url
        @url ||= URI.parse(@options.fetch('url'))
      end

      def hostname
        @hostname ||= @options['hostname'] || Socket.gethostname
      end

      def start_thread
        @thread = Thread.start do
          begin
            count = INTERVAL
            until @stop
              if 0 < count
                count -= 1
              else
                flush_events
                count = INTERVAL
              end

              sleep 1
            end
            flush_events
          rescue Exception => err
            Itamae.logger.error "Error during sending events to Itamae Server: #{err}"
          end
        end

        @thread.abort_on_exception = true
        at_exit do
          @stop = true
          @thread.join
        end
      end

      def flush_events
        events = @events
        @events = []

        return if events.empty?

        res = conn.post do |req|
          req.url url.path
          req.headers['Content-Type'] = 'application/json'
          req.body = {
            'host' => hostname,
            'events' => events.map {|e| {'type' => e[0], 'payload' => e[1]} },
          }.to_json
        end

        unless 200 <= res.status && res.status < 300
          raise "Invalid response code from Itamae Server: #{res.status}\n#{res.body}"
        end
      end
    end
  end
end
