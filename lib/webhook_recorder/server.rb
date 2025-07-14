require 'webhook_recorder/version'
require 'rack'
require 'rack/handler/puma'
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
      @app = proc { |env| call(env) }
      
      # Use Rack with Puma handler for better performance
      # This needs to run in a thread because Rack::Handler::Puma.run is blocking
      @server_thread = Thread.new do
        Rack::Handler::Puma.run(
          @app,
          Host: 'localhost',
          Port: @port,
          Threads: '1:4',
          Quiet: !self.log_verbose
        )
      rescue => e
        puts "Server error: #{e.message}"
        puts e.backtrace
      end
      
      @started = true
    end

    def wait
      Timeout.timeout(10) do 
        sleep 0.1 until @started 
        sleep 0.5  # Give server a moment to fully start
      end
    end

    def call(env)
      path = env['PATH_INFO']
      request = Rack::Request.new(env)
      
      # Read the body properly for Puma
      request_body = request.body.read
      request.body.rewind if request.body.respond_to?(:rewind)
      
      # Store request details for recording
      request_data = {
        request_path: path,
        query_string: env['QUERY_STRING'],
        http_user_agent: env['HTTP_USER_AGENT'],
        request_body: request_body,
        request_method: env['REQUEST_METHOD'],
        content_type: env['CONTENT_TYPE'],
        remote_addr: env['REMOTE_ADDR']
      }.merge(env.select { |k, v| k.start_with?('HTTP_') })
      
      recorded_reqs << request_data.with_indifferent_access
      
      if response_config[path]
        res = response_config[path]
        [res[:code], res[:headers] || {}, [res[:body] || "Missing body in response_config"]]
      else
        warn "WebhookRecorder::Server: Missing response_config for path #{path}"
        [404, {}, ["WebhookRecorder::Server: Missing response_config for path #{path}"]]
      end
    end

    def stop
      if @server_thread
        @server_thread.kill
        @server_thread = nil
      end
      @started = false
    end
  end
end
