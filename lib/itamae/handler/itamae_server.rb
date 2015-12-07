require "itamae/handler/base"
require "itamae/handler/itamae_server/version"

require "uri"
require "faraday"
require "socket"
require "json"
require "thread"

module Itamae
  module Handler
    class ItamaeServer < Base
      INTERVAL = 10

      def initialize(*)
        super
        @mutex = Mutex.new
        @events = []
        start_thread
      end

      def event(type, payload = {})
        super

        @mutex.synchronize do
          @events << [type, payload]
        end
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
            Itamae.logger.warn "Error during sending events to Itamae Server: #{err}\n#{err.backtrace.join("\n")}"
          end
        end

        @thread.abort_on_exception = true
        at_exit do
          @stop = true
          @thread.join
        end
      end

      def flush_events
        events = nil
        @mutex.synchronize do
          events = @events
          @events = []
        end

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
          @mutex.synchronize do
            @events = events + @events
          end
          Itamae.logger.warn "Invalid response code from Itamae Server: #{res.status}\n#{res.body}"
        end
      end
    end
  end
end
