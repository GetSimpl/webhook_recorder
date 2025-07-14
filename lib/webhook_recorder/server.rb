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

    def initialize(port, response_config = {}, http_expose = true, log_verbose = false)
      self.port = port
      self.response_config = response_config
      self.recorded_reqs = []
      self.http_expose = http_expose
      self.log_verbose = log_verbose
      @started = false
      @config_mutex = Mutex.new
    end
    
    # Class-level shared server - Server.open creates and reuses this by default
    @@shared_server = nil
    @@shared_server_mutex = Mutex.new

    def self.open(port: nil, response_config: nil, http_expose: true, log_verbose: false, ngrok_token: nil)
      @@shared_server_mutex.synchronize do
        # If a specific port is requested and we have a server on a different port, stop the old one
        if @@shared_server && port && @@shared_server.port != port
          @@shared_server.stop
          @@shared_server = nil
        end
        
        unless @@shared_server
          @@shared_server = new(port || find_available_port, {}, http_expose, log_verbose)
          @@shared_server.start
          @@shared_server.wait
          
          # Setup cleanup at program exit
          at_exit { stop_shared_server }
        end
        
        # Update the response config for this call
        @@shared_server.update_response_config(response_config || {})
        
        # Handle ngrok if needed and not already enabled
        if http_expose && !@@shared_server.http_expose
          @@shared_server.http_expose = true
          Ngrok::Wrapper.start(port: @@shared_server.port, authtoken: ngrok_token || "2ziwSjEiokbqkXYy3V91BRaSPhX_6o1ViSr39f4QdQjxrDUhE" || ENV['NGROK_AUTH_TOKEN'], config: ENV['NGROK_CONFIG_FILE'])
          @@shared_server.http_url = Ngrok::Wrapper.ngrok_url
          @@shared_server.https_url = Ngrok::Wrapper.ngrok_url_https
        end
        
        yield @@shared_server
      end
    end

    def self.stop_shared_server
      @@shared_server_mutex.synchronize do
        if @@shared_server
          @@shared_server.stop
          @@shared_server = nil
        end
      end
    end

    def self.find_available_port
      require 'socket'
      server = TCPServer.new('localhost', 0)
      port = server.addr[1]
      server.close
      port
    end

    # Add method to update response config dynamically
    def update_response_config(new_config)
      @config_mutex.synchronize do
        self.response_config = new_config
        clear_recorded_requests
      end
    end

    # Add method to clear recorded requests
    def clear_recorded_requests
      self.recorded_reqs.clear
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
      
      # Store request details for recording (thread-safe)
      request_data = {
        request_path: path,
        query_string: env['QUERY_STRING'],
        http_user_agent: env['HTTP_USER_AGENT'],
        request_body: request_body,
        request_method: env['REQUEST_METHOD'],
        content_type: env['CONTENT_TYPE'],
        remote_addr: env['REMOTE_ADDR']
      }.merge(env.select { |k, v| k.start_with?('HTTP_') })
      
      @config_mutex.synchronize do
        recorded_reqs << request_data.with_indifferent_access
      end
      
      # Get response config in thread-safe manner
      current_response_config = @config_mutex.synchronize { response_config.dup }
      
      if current_response_config[path]
        res = current_response_config[path]
        [res[:code], res[:headers] || {}, [res[:body] || "Missing body in response_config"]]
      else
        warn "WebhookRecorder::Server: Missing response_config for path #{path}"
        [404, {}, ["WebhookRecorder::Server: Missing response_config for path #{path}"]]
      end
    end

    def stop
      if @server_thread
        @server_thread.kill
        @server_thread.join(2) # Wait up to 2 seconds for clean shutdown
        @server_thread = nil
      end
      @started = false
      # Give the port time to be released
      sleep 0.1
    end
  end
end
