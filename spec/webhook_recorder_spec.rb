require 'spec_helper'

RSpec.describe WebhookRecorder do
  before do
    @port = 4501
  end

  it 'has a version number' do
    expect(WebhookRecorder::VERSION).not_to be nil
  end

  context 'open' do
    it 'should respond as defined as response_config' do
      response_config = { '/hello' => { code: 200, body: 'Expected result' } }
      WebhookRecorder::Server.open(port: @port, response_config: response_config, http_expose: false) do |server|
        local_url = "http://localhost:#{server.port}"

        res = HTTPX.post("#{local_url}/hello?q=1", json: {some: 1, other: 2})

        expect(res.status).to eq(200)
        expect(res.body.to_s).to eq('Expected result')
        expect(server.recorded_reqs.size).to eq(1)
        req1 = server.recorded_reqs.first
        expect(req1[:path_info]).to eq('/hello')
        expect(req1[:query_string]).to include('q=1')
        expect(req1[:http_user_agent]).to include('httpx')
        expect(JSON.parse(req1[:request_body]).symbolize_keys).to eq({some: 1, other: 2})
      end
    end

    it 'should run in localhost if ngrok option is toggled off' do
      response_config = { '/hello' => { code: 200, body: 'Expected result' } }
      WebhookRecorder::Server.open(port: @port, response_config: response_config, http_expose: false) do |server|
        expect(server.http_url).to be_nil
        expect(server.https_url).to be_nil

        res = HTTPX.post("http://localhost:#{@port}/hello?q=1", json: {some: 1, other: 2})

        expect(res.status).to eq(200)
        expect(res.body.to_s).to eq('Expected result')
        expect(server.recorded_reqs.size).to eq(1)
        req1 = server.recorded_reqs.first
        expect(req1[:path_info]).to eq('/hello')
        expect(req1[:query_string]).to include('q=1')
        expect(req1[:http_user_agent]).to include('httpx')
        expect(JSON.parse(req1[:request_body]).symbolize_keys).to eq({some: 1, other: 2})
      end
    end

    it 'should respond with 404 if not configured' do
      WebhookRecorder::Server.open(port: @port, response_config: {}, http_expose: false) do |server|
        local_url = "http://localhost:#{server.port}"

        res = HTTPX.get("#{local_url}/hello")
        expect(res.status).to eq(404)
      end
    end

    it 'should expose server via ngrok when http_expose is true' do
      response_config = { '/webhook' => { code: 200, body: 'Webhook received via ngrok' } }
      WebhookRecorder::Server.open(port: @port, response_config: response_config, http_expose: true) do |server|
        # When http_expose is true, ngrok URLs should be available
        expect(server.https_url).not_to be_nil
        expect(server.https_url).to include('ngrok')
        
        # Test that the ngrok URL works
        res = HTTPX.post("#{server.https_url}/webhook", json: {ngrok: true, test: 'data'})

        expect(res.status).to eq(200)
        expect(res.body.to_s).to eq('Webhook received via ngrok')
        expect(server.recorded_reqs.size).to eq(1)
        req1 = server.recorded_reqs.first
        expect(req1[:path_info]).to eq('/webhook')
        expect(req1[:http_user_agent]).to include('httpx')
        expect(JSON.parse(req1[:request_body]).symbolize_keys).to eq({ngrok: true, test: 'data'})
      end
    end
  end
end
