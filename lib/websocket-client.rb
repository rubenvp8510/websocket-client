require 'event_emitter'
require 'websocket/driver'
require 'net/http'


module SyncWebSocket
  class Client

    include EventEmitter
    attr_reader :url, :secured

    RECV_BUFFER_SIZE=4096
    HANDSHAKE_TIMEOUT=20

    def self.connect(url, options = {}, timeout=20)
      client = SyncWebSocket::Client.new
      yield client if block_given?
      client.connect url, options, timeout
      client
    end

    def connect(url, options = {}, timeout)
      return if @socket
      @open = false
      @url = url
      uri = URI.parse url
      port = uri.port || (uri.scheme == 'wss' ? 443 : 80)
      host = uri.host
      @secured = false
      create_socket(host, port, timeout)
      if %w(https wss).include? uri.scheme
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = options[:ssl_version] || 'SSLv23'
        ctx.verify_mode = options[:verify_mode] || OpenSSL::SSL::VERIFY_NONE #use VERIFY_PEER for verification
        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths
        ctx.cert_store = cert_store
        @socket = ::OpenSSL::SSL::SSLSocket.new(@socket, ctx)
        @socket.connect
        @secured = true
      end

      @driver = WebSocket::Driver.client(self, options)
      set_headers(options[:headers]) unless options[:headers].nil?
      @thread = Thread.current
      @driver.start
      once :__close do |err|
        close
        emit :close, err
      end
      start_reading_data
      sleep HANDSHAKE_TIMEOUT
      @open = true
    end


    def write(string)
      begin
        @socket.write(string) unless @socket.closed?
      rescue Errno::EPIPE => _e
        @pipe_broken = true
        emit :close
      end
    end

    def send(payload)
      case payload
      when Numeric then
        @driver.text(payload.to_s)
      when String then
        @driver.text(payload)
      when Array then
        @driver.binary(payload)
      else
        false
      end
    end

    def text(payload)
      case payload
      when Numeric then
        @driver.text(payload.to_s)
      when String then
        @driver.text(payload)
      else
        false
      end
    end

    def binary(payload)
      case payload
      when Array then
        @driver.binary(payload)
      when Numeric then
        @driver.binary(payload.to_s.bytes)
      when String then
        @driver.binary(payload.bytes)
      else
        false
      end
    end

    def sync_text(payload, response_timeout=20)
      message = nil
      self.once :message do |msg|
        message = msg
        @thread.wakeup
      end
      self.text(payload)
      sleep response_timeout
      return message
    end

    def sync_binary(payload, response_timeout=20)
      message = nil
      self.once :message do |msg|
        message = msg
        @thread.wakeup
      end
      self.binary(payload)
      sleep response_timeout
      return message
    end

    def close
      Thread.kill @data_thread if @data_thread
      @socket.close if @socket
      @driver.close
      @socket = nil
    end

    private

    def start_reading_data
      @data_thread = Thread.new do
        @driver.on :message, -> (e) { emit :message, e.data }
        @driver.on :open, ->(_e) { @thread.wakeup }
        while true do
          begin
            data = @socket.readpartial RECV_BUFFER_SIZE unless @socket.closed?
            @driver.parse data unless @socket.closed?
          rescue Exception
            break
          end
        end
      end
    end

    def create_socket(host, port, timeout=20)
      family = Socket::AF_INET
      address = Socket.getaddrinfo(host, nil, family).first[3]
      @sockaddr = Socket.pack_sockaddr_in(port, address)
      @socket = Socket.new(family, Socket::SOCK_STREAM, 0)
      @socket.setsockopt(Socket::IPPROTO_TCP, Socket::TCP_NODELAY, 1)

      begin
        @socket.connect_nonblock(@sockaddr)
      rescue Errno::EINPROGRESS
        select_timeout(:connect, timeout)
      end

      begin
        @socket.connect_nonblock(@sockaddr)
      rescue Errno::EISCONN
        # Successfully connected
      end
    end

    def select_timeout(type, timeout)
      if timeout >= 0
        if type == :read
          read_array = [@socket]
        else
          write_array = [@socket]
        end

        start = Time.now
        if IO.select(read_array, write_array, [@socket], timeout)
          waited = Time.now - start
          return timeout - waited
        end
      end
      raise SocketTimeout, "#{type} timeout"
    end

    def set_headers(headers)
      headers.each do |k, v|
        @driver.set_header(k, v)
      end
    end
  end
end
