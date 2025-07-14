require 'webhook_recorder/version'
require 'rack'
require 'webrick'
require 'ngrok/wrapper'
require 'active_support/core_ext/hash'
require 'timeout'
require 'stringio'

module WebhookRecorder
  class Server
    attr_accessor :recorded_reqs, :http_url, :https_url, :response_config,
                  :port, :http_expose, :log_verbose

    def initialize(port, response_config, http_expose = true, log_verbose = false)
      self.port = port
      self.response_config = response_config
      self.recorded_reqs = []
      self.http_expose = http_expose
      self.log_verbose = log_verbose
      @started = false
    end
    
    def self.open(port: nil, response_config: nil, http_expose: true, log_verbose: false, ngrok_token: nil)
      server = new(port, response_config, http_expose, log_verbose)
      server.start
      server.wait
      if server.http_expose
        Ngrok::Wrapper.start(port: port, authtoken: ngrok_token || ENV['NGROK_AUTH_TOKEN'], config: ENV['NGROK_CONFIG_FILE'])
        server.http_url = Ngrok::Wrapper.ngrok_url
        server.https_url = Ngrok::Wrapper.ngrok_url_https
      end
      yield server
    ensure
      server.recorded_reqs.clear if server
      server.stop if server
      if server&.http_expose
        Ngrok::Wrapper.stop
      end
    end

    def start
      Thread.new do
        @webrick_server = WEBrick::HTTPServer.new(
          Port: @port,
          Logger: WEBrick::Log.new(self.log_verbose ? $stdout : "/dev/null"),
          AccessLog: [],
          DoNotReverseLookup: true
        )
        
        @webrick_server.mount_proc '/' do |req, res|
          rack_env = {}
          
          # Build basic Rack env
          rack_env['REQUEST_METHOD'] = req.request_method
          rack_env['PATH_INFO'] = req.path
          rack_env['REQUEST_PATH'] = req.path
          rack_env['QUERY_STRING'] = req.query_string || ''
          rack_env['SERVER_NAME'] = req.host
          rack_env['SERVER_PORT'] = @port.to_s
          rack_env['HTTP_USER_AGENT'] = req['User-Agent'] || ''
          rack_env['CONTENT_TYPE'] = req['Content-Type'] || ''
          rack_env['CONTENT_LENGTH'] = req['Content-Length'] || ''
          rack_env['REQUEST_URI'] = req.request_uri.to_s
          rack_env['HTTP_HOST'] = req['Host'] || ''
          rack_env['SCRIPT_NAME'] = ''
          rack_env['REMOTE_ADDR'] = req.peeraddr[3] rescue '127.0.0.1'
          rack_env['rack.version'] = [1, 3]
          rack_env['rack.url_scheme'] = 'http'
          rack_env['rack.multithread'] = true
          rack_env['rack.multiprocess'] = false
          rack_env['rack.run_once'] = false
          rack_env['rack.errors'] = $stderr
          
          # Add headers
          req.each do |key, value|
            key = key.upcase.gsub('-', '_')
            key = "HTTP_#{key}" unless %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
            rack_env[key] = value
          end
          
          # Handle request body
          rack_env['rack.input'] = StringIO.new(req.body || '')
          rack_env['request_body'] = req.body || ''
          
          # Call the rack app
          status, headers, body = call(rack_env)
          
          res.status = status
          headers.each { |k, v| res[k] = v }
          res.body = body.is_a?(Array) ? body.join : body.to_s
        end
        
        @server = @webrick_server
        @started = true
        @webrick_server.start
      rescue => e
        puts "Server error: #{e.message}"
        puts e.backtrace
      end
    end

    def wait
      Timeout.timeout(10) { sleep 0.1 until @started }
    end

    def call(env)
      path = env['PATH_INFO']
      request = Rack::Request.new(env)
      recorded_reqs << env.merge(request_body: request.body.string).deep_transform_keys(&:downcase).with_indifferent_access
      if response_config[path]
        res = response_config[path]
        [res[:code], res[:headers] || {}, [res[:body] || "Missing body in response_config"]]
      else
        warn "WebhookRecorder::Server: Missing response_config for path #{path}"
        [404, {}, ["WebhookRecorder::Server: Missing response_config for path #{path}"]]
      end
    end

    def stop
      @server.shutdown if @server
    end
  end
end
