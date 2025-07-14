require 'spec_helper'

# YOUR PERFECT TESTING PATTERN
# Just use Server.open as normal - it automatically reuses servers!

RSpec.describe "Your Perfect Testing Pattern" do
  
  # Start ONE shared server for all tests (optional - Server.open will create one if needed)
  before(:all) do
    WebhookRecorder::Server.shared_server(http_expose: false)
  end

  it "test payment webhook" do
    WebhookRecorder::Server.open(
      response_config: { '/payment' => { code: 200, body: { success: true }.to_json } },
      http_expose: false
    ) do |server|
      response = HTTPX.post("http://localhost:#{server.port}/payment", json: { amount: 100 })
      
      expect(response.status).to eq(200)
      expect(JSON.parse(response.body.to_s)['success']).to be true
      expect(server.recorded_reqs.size).to eq(1)
    end
  end

  it "test user creation webhook" do
    WebhookRecorder::Server.open(
      response_config: { '/user' => { code: 201, body: { id: 456 }.to_json } },
      http_expose: false
    ) do |server|
      response = HTTPX.post("http://localhost:#{server.port}/user", json: { name: 'John' })
      
      expect(response.status).to eq(201)
      expect(JSON.parse(response.body.to_s)['id']).to eq(456)
      expect(server.recorded_reqs.size).to eq(1)
    end
  end

  it "test error handling" do
    WebhookRecorder::Server.open(
      response_config: { '/error' => { code: 422, body: { error: 'Invalid data' }.to_json } },
      http_expose: false
    ) do |server|
      response = HTTPX.post("http://localhost:#{server.port}/error", json: { bad: 'data' })
      
      expect(response.status).to eq(422)
      expect(JSON.parse(response.body.to_s)['error']).to eq('Invalid data')
    end
  end

  it "test multiple endpoints in one test" do
    WebhookRecorder::Server.open(
      response_config: {
        '/create' => { code: 201, body: 'Created' },
        '/update' => { code: 200, body: 'Updated' },
        '/delete' => { code: 204, body: '' }
      },
      http_expose: false
    ) do |server|
      create_resp = HTTPX.post("http://localhost:#{server.port}/create", json: {})
      update_resp = HTTPX.put("http://localhost:#{server.port}/update", json: {})
      delete_resp = HTTPX.delete("http://localhost:#{server.port}/delete")
      
      expect(create_resp.status).to eq(201)
      expect(update_resp.status).to eq(200)
      expect(delete_resp.status).to eq(204)
      expect(server.recorded_reqs.size).to eq(3)
    end
  end
end
