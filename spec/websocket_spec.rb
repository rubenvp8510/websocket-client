require 'websocket_client'
describe SyncWebSocket::Client do
  it 'cannot open a connection to the wrong host' do
    expect { SyncWebSocket::Client.connect 'ws://localhost' }
      .to raise_exception(SyncWebSocket::ConnectionError)
    expect { SyncWebSocket::Client.connect 'ws://not-exist.host.com' }
      .to raise_exception(SyncWebSocket::ConnectionError)
  end

  it 'can open a connection' do
    ws = SyncWebSocket::Client.connect 'ws://echo.websocket.org'
    expect(ws.open?).to be true
  end

  it 'can close the connection' do
    ws = SyncWebSocket::Client.connect 'ws://echo.websocket.org'
    ws.close
    expect(ws.open?).to be false
  end

  it 'can open ssl connection' do
    ws = SyncWebSocket::Client.connect 'wss://echo.websocket.org'
    ws.close
    expect(ws.open?).to be false
  end

  describe 'in the OPEN state' do
    it 'can send and receive messages' do
      ws = SyncWebSocket::Client.connect 'ws://echo.websocket.org'
      response = ws.sync_text 'hello world'
      expect(response).to eq 'hello world'
    end

    it 'sends numbers and strings as text' do
      ws = SyncWebSocket::Client.connect 'ws://echo.websocket.org'
      response = ws.sync_text 100
      expect(response).to eq '100'
      response = ws.sync_text 'again'
      expect(response).to eq 'again'
    end

    it 'sends numbers and strings as binary' do
      ws = SyncWebSocket::Client.connect 'ws://echo.websocket.org'
      response = ws.sync_binary 100
      expect(response).to eq '100'.bytes
      response = ws.sync_binary 'again'
      expect(response).to eq 'again'.bytes
    end
  end
end
