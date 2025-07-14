require 'spec_helper'

# PERFECT: This is exactly what you wanted!
# Server.open will reuse existing server and just update config

RSpec.describe "Server.open with Auto-Reuse" do
  
  # This will start the shared server
  before(:all) do
    # Start a shared server first via Server.open
    WebhookRecorder::Server.open(response_config: {}, http_expose: false) do |server|
      @initial_server = server
      puts "🚀 Initial server started on port: #{@initial_server.port}"
    end
  end

  it "first call to Server.open creates/uses server" do
    response_config = { '/test1' => { code: 200, body: 'Test 1 response' } }
    
    WebhookRecorder::Server.open(response_config: response_config, http_expose: false) do |server|
      # This should reuse the existing shared server
      expect(server.port).to eq(@initial_server.port)
      puts "✅ Server.open reused existing server on port: #{server.port}"
      
      # Test the webhook
      response = HTTPX.post("http://localhost:#{server.port}/test1", json: { data: 'test1' })
      expect(response.status).to eq(200)
      expect(response.body.to_s).to eq('Test 1 response')
      expect(server.recorded_reqs.size).to eq(1)
    end
  end

  it "second call to Server.open reuses same server with new config" do
    response_config = { '/test2' => { code: 201, body: 'Test 2 response' } }
    
    WebhookRecorder::Server.open(response_config: response_config, http_expose: false) do |server|
      # Should be the same server instance
      expect(server.port).to eq(@initial_server.port)
      expect(server).to eq(@initial_server)
      puts "✅ Server.open reused same server again on port: #{server.port}"
      
      # The config should be updated to the new one
      response = HTTPX.post("http://localhost:#{server.port}/test2", json: { data: 'test2' })
      expect(response.status).to eq(201)
      expect(response.body.to_s).to eq('Test 2 response')
      
      # Previous requests should be cleared (due to update_response_config)
      expect(server.recorded_reqs.size).to eq(1)
      expect(server.recorded_reqs.first[:request_path]).to eq('/test2')
    end
  end

  it "third call with different config again" do
    response_config = { 
      '/test3' => { code: 200, body: { success: true, id: 123 }.to_json },
      '/error' => { code: 422, body: { error: 'Validation failed' }.to_json }
    }
    
    WebhookRecorder::Server.open(response_config: response_config, http_expose: false) do |server|
      expect(server.port).to eq(@initial_server.port)
      puts "✅ Server.open reused server with multiple endpoints"
      
      # Test multiple endpoints
      success_response = HTTPX.post("http://localhost:#{server.port}/test3", json: {})
      error_response = HTTPX.post("http://localhost:#{server.port}/error", json: {})
      
      expect(success_response.status).to eq(200)
      expect(error_response.status).to eq(422)
      
      expect(server.recorded_reqs.size).to eq(2)
    end
  end

  it "works seamlessly with your existing test pattern" do
    # This is exactly how you can write your tests now
    
    WebhookRecorder::Server.open(
      response_config: { '/payment' => { code: 200, body: { status: 'paid' }.to_json } },
      http_expose: false
    ) do |server|
      response = HTTPX.post("http://localhost:#{server.port}/payment", 
                           json: { amount: 100, currency: 'USD' })
      
      expect(response.status).to eq(200)
      expect(JSON.parse(response.body.to_s)['status']).to eq('paid')
      
      # Verify webhook was recorded
      expect(server.recorded_reqs.size).to eq(1)
      payment_req = server.recorded_reqs.first
      expect(payment_req[:request_path]).to eq('/payment')
      expect(JSON.parse(payment_req[:request_body])['amount']).to eq(100)
    end
  end
end
