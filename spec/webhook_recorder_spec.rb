require 'spec_helper'

RSpec.describe WebhookRecorder do
  before do
    @port = rand(49152..65535)  # Use random available port range
  end

  it 'has a version number' do
    expect(WebhookRecorder::VERSION).not_to be nil
  end

  context 'open' do
    it 'should respond as defined as response_config' do
      response_config = { '/hello' => { code: 200, body: 'Expected result' } }
      WebhookRecorder::Server.open(port: @port, response_config: response_config) do |server|
        expect(server.https_url).not_to be_nil

        res = HTTPX.post("#{server.https_url}/hello?q=1", json: {some: 1, other: 2})

        expect(res.status).to eq(200)
        expect(res.body.to_s).to eq('Expected result')
        expect(server.recorded_reqs.size).to eq(1)
        req1 = server.recorded_reqs.first
        expect(req1[:request_path]).to eq('/hello')
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
        expect(req1[:request_path]).to eq('/hello')
        expect(req1[:query_string]).to include('q=1')
        expect(req1[:http_user_agent]).to include('httpx')
        expect(JSON.parse(req1[:request_body]).symbolize_keys).to eq({some: 1, other: 2})
      end
    end

    it 'should respond with 404 if not configured' do
      WebhookRecorder::Server.open(port: @port, response_config: {}) do |server|
        expect(server.https_url).not_to be_nil

        res = HTTPX.get("#{server.https_url}/hello")
        expect(res.status).to eq(404)
      end
    end
  end
end
