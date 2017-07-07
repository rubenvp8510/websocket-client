require 'spec_helper'
require 'websocket_client'
WAITING_TIME_FOR_ASYNC = 30
[:secure, :non_secure].each do |security_context|
  describe SyncWebSocket::Client do
    let(:security_prefix) do
      security_context == :secure ? 'wss' : 'ws'
    end

    describe "Testing connection for context #{security_context}" do
      it 'cannot open a connection to the wrong host' do
        expect { SyncWebSocket::Client.connect "#{security_prefix}://localhost" }
          .to raise_exception(SyncWebSocket::ConnectionError)
        expect { SyncWebSocket::Client.connect "#{security_prefix}://not-exist.host.com" }
          .to raise_exception(SyncWebSocket::ConnectionError)
      end

      it 'cannot open a connection in wrong port' do
        expect do
          SyncWebSocket::Client.connect "#{security_prefix}://echo.websocket.org:1283", {}, 1
        end.to raise_exception SyncWebSocket::ConnectionError
      end

      it 'can open a connection' do
        ws = SyncWebSocket::Client.connect "#{security_prefix}://echo.websocket.org"
        expect(ws.open?).to be true
      end

      it 'can open a connection with headers' do
        ws_options = {
          headers:  {
            'Authorization' => 'Basic ' + 'XXX',
            'Hawkular-Tenant' => 'hawkular',
            'Accept' => 'application/json'
          }
        }
        ws = SyncWebSocket::Client.connect "#{security_prefix}://echo.websocket.org", ws_options
        expect(ws.open?).to be true
      end

      it 'can open a connection with port' do
        ws = SyncWebSocket::Client.connect "#{security_prefix}://echo.websocket.org"
        expect(ws.open?).to be true
      end

      it 'can close the connection' do
        ws = SyncWebSocket::Client.connect "#{security_prefix}://echo.websocket.org"
        ws.close
        expect(ws.open?).to be false
      end
    end

    describe "Testing sending/receiving data for context #{security_context}" do
      before(:each) do
        protocol = :secure ? 'wss' : 'ws'
        @ws = SyncWebSocket::Client.connect "#{protocol}://echo.websocket.org"
      end

      after(:each) do
        @ws.close
      end

      it 'can send and receive messages in sync manner' do
        response = @ws.sync_text 'hello world'
        expect(response).to eq 'hello world'
      end

      it 'sends numbers and strings as text in sync manner' do
        response = @ws.sync_text 100
        expect(response).to eq '100'
        response = @ws.sync_text 'again'
        expect(response).to eq 'again'
      end

      it 'sends numbers and strings as binary in sync manner' do
        response = @ws.sync_binary 100
        expect(response).to eq '100'.bytes
        response = @ws.sync_binary 'again'
        expect(response).to eq 'again'.bytes
      end

      # Async manner

      it 'can send and receive strings in async manner' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.text 'hello world'
        sleep 20
        expect(message).to eq 'hello world'
      end

      it 'can send and receive numbers in async manner' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.text 100
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq '100'
        message = nil
        @ws.text 'again'
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq 'again'
      end

      it 'can send and receive arrays in async manner' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.binary [72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100]

        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq [72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100]
        message = nil
        @ws.binary 'again'
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq 'again'.bytes
      end

      it 'using generic send for send text' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.send('Hello world')
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq 'Hello world'
      end

      it 'using generic send for send an array' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.send([72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100])
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq [72, 101, 108, 108, 111, 44, 32, 119, 111, 114, 108, 100]
      end

      it 'using generic send for send a number' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        @ws.send(18)
        sleep WAITING_TIME_FOR_ASYNC
        expect(message).to eq '18'
      end

      it 'using generic send for send invalid object' do
        message = nil
        th = Thread.current
        @ws.on :message do |msg|
          message = msg
          th.wakeup
        end
        sended = @ws.send(nil)
        expect(sended).to be_falsey
        sleep 2
        expect(message).to eq nil
      end
    end
  end
end
