require 'spec_helper'

# ULTIMATE SIMPLICITY: Server.open always uses shared server by default
# This is the cleanest possible pattern for your testing

RSpec.describe "Server.open Always Shared (Default Behavior)" do

  it "first Server.open call creates shared server" do
    WebhookRecorder::Server.open(
      port: 4567,
      response_config: { '/test1' => { code: 200, body: 'First test' } },
      http_expose: false
    ) do |server|
      puts "🚀 First call - Server port: #{server.port}"
      expect(server.port).to eq(4567)
      
      response = HTTPX.post("http://localhost:#{server.port}/test1", json: { data: 'test1' })
      expect(response.status).to eq(200)
      expect(response.body.to_s).to eq('First test')
      expect(server.recorded_reqs.size).to eq(1)
    end
  end

  it "second Server.open call reuses same shared server" do
    WebhookRecorder::Server.open(
      port: 4567,  # Same port - should reuse existing server
      response_config: { '/test2' => { code: 201, body: 'Second test' } },
      http_expose: false
    ) do |server|
      puts "🔄 Second call - Server port: #{server.port} (should be same)"
      expect(server.port).to eq(4567)
      
      response = HTTPX.post("http://localhost:#{server.port}/test2", json: { data: 'test2' })
      expect(response.status).to eq(201)
      expect(response.body.to_s).to eq('Second test')
      
      # Previous requests cleared due to update_response_config
      expect(server.recorded_reqs.size).to eq(1)
      expect(server.recorded_reqs.first[:path_info]).to eq('/test2')
    end
  end

  it "third Server.open call - still same server" do
    WebhookRecorder::Server.open(
      port: 4567,  # Same port - should reuse existing server
      response_config: { 
        '/payment' => { code: 200, body: { success: true, amount: 100 }.to_json },
        '/error' => { code: 422, body: { error: 'Invalid' }.to_json }
      },
      http_expose: false
    ) do |server|
      puts "✅ Third call - Server port: #{server.port} (same server, new config)"
      expect(server.port).to eq(4567)
      
      # Test multiple endpoints
      payment_resp = HTTPX.post("http://localhost:#{server.port}/payment", json: { amount: 100 })
      error_resp = HTTPX.post("http://localhost:#{server.port}/error", json: { bad: 'data' })
      
      expect(payment_resp.status).to eq(200)
      expect(error_resp.status).to eq(422)
      
      expect(JSON.parse(payment_resp.body.to_s)['success']).to be true
      expect(JSON.parse(error_resp.body.to_s)['error']).to eq('Invalid')
      
      expect(server.recorded_reqs.size).to eq(2)
    end
  end

  it "you can now write tests exactly as you wanted" do
    # This is your perfect, clean testing pattern
    WebhookRecorder::Server.open(
      response_config: { '/webhook/user' => { code: 201, body: { id: 456, name: 'John' }.to_json } },
      http_expose: false
    ) do |server|
      # Make your webhook call
      response = HTTPX.post("http://localhost:#{server.port}/webhook/user", 
                           json: { name: 'John Doe', email: 'john@example.com' })
      
      # Verify response
      expect(response.status).to eq(201)
      user_data = JSON.parse(response.body.to_s)
      expect(user_data['id']).to eq(456)
      expect(user_data['name']).to eq('John')
      
      # Verify webhook was recorded
      expect(server.recorded_reqs.size).to eq(1)
      webhook_req = server.recorded_reqs.first
      expect(webhook_req[:path_info]).to eq('/webhook/user')
      expect(webhook_req[:request_method]).to eq('POST')
      
      request_body = JSON.parse(webhook_req[:request_body])
      expect(request_body['name']).to eq('John Doe')
      expect(request_body['email']).to eq('john@example.com')
    end
  end

  it "no setup needed - just use Server.open directly" do
    WebhookRecorder::Server.open(
      port: 4567,  # Same port - should reuse existing server
      response_config: { '/simple' => { code: 200, body: 'Simple response' } },
      http_expose: false
    ) do |server|
      expect(server.port).to eq(4567)
      response = HTTPX.get("http://localhost:#{server.port}/simple")
      expect(response.status).to eq(200)
      expect(response.body.to_s).to eq('Simple response')
    end
  end

  it "requesting different port creates new shared server" do
    WebhookRecorder::Server.open(
      port: 4568,  # Different port - should create new server
      response_config: { '/different' => { code: 200, body: 'Different port response' } },
      http_expose: false
    ) do |server|
      puts "🔀 Different port requested - Server port: #{server.port}"
      expect(server.port).to eq(4568)
      
      response = HTTPX.get("http://localhost:#{server.port}/different")
      expect(response.status).to eq(200)
      expect(response.body.to_s).to eq('Different port response')
    end
  end
end
