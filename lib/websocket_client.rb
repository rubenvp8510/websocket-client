# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

require 'event_emitter'
require 'websocket/driver'
require 'net/http'
require 'resolv'
require 'ipaddr'
require 'socket'
require 'openssl'

module SyncWebSocket
  class ConnectionError < RuntimeError
  end

  class Client
    include EventEmitter
    attr_reader :url, :secured, :open
    alias_method :open?, :open

    RECV_BUFFER_SIZE = 4096
    HANDSHAKE_TIMEOUT = 20

    DEFAULT_CLOSE_TIMEOUT = 20
    DEFAULT_CONNECTION_TIMEOUT = 20
    DEFAULT_RESPONSE_TIMEOUT = 10

    DEFAULT_SSL_PORT = 443
    DEFAULT_HTTP_PORT = 80

    def self.connect(url, options = {}, timeout = DEFAULT_CONNECTION_TIMEOUT)
      client = SyncWebSocket::Client.new
      yield client if block_given?
      client.connect url, timeout, options
      client
    end

    def connect(url, timeout, options = {})
      return if @socket
      @open = false
      @url = url
      uri = URI.parse url
      @secured = %w(https wss).include? uri.scheme
      port = uri.port || (@secured ? DEFAULT_SSL_PORT : DEFAULT_HTTP_PORT)
      host = uri.host
      create_socket(host, port, timeout)
      if @secured
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = options[:ssl_version] || 'SSLv23'
        ctx.verify_mode = options[:verify_mode] || OpenSSL::SSL::VERIFY_NONE
        cert_store = OpenSSL::X509::Store.new
        cert_store.set_default_paths
        ctx.cert_store = cert_store
        @socket = ::OpenSSL::SSL::SSLSocket.new(@socket, ctx)
        @socket.connect
      end
      headers = options[:headers] || {}
      options.delete(:headers)
      @driver = WebSocket::Driver.client(self, options)
      process_headers(headers)
      thread = Thread.current
      @driver.start

      once :__close do |err|
        close
        emit :close, err
      end

      @driver.on :open, lambda { |_e|
        @open = true
        thread.wakeup
      }

      start_reading_data
      sleep HANDSHAKE_TIMEOUT
      raise ConnectionError, 'Handshake timeout' unless @open
    end

    def write(string)
      @socket.write(string) unless @socket.closed?
    rescue Errno::EPIPE => e
      @pipe_broken = true
      emit :close, e
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

    def sync_text(payload, response_timeout = DEFAULT_RESPONSE_TIMEOUT)
      sync_method(response_timeout) do
        text(payload)
      end
    end

    def sync_binary(payload, response_timeout = DEFAULT_RESPONSE_TIMEOUT)
      sync_method(response_timeout) do
        binary(payload)
      end
    end

    def close(timeout = DEFAULT_CLOSE_TIMEOUT)
      thread = Thread.current
      @driver.on :close do
        @open = false
        thread.wakeup
      end
      @driver.close
      sleep timeout
      Thread.kill @data_thread if @data_thread
      @data_thread.join
      @data_thread = nil
      @socket && (@secured ? @socket.sync_close : @socket.close)
      @socket = nil
      emit :close
    end

    private

    def sync_method(response_timeout = DEFAULT_RESPONSE_TIMEOUT)
      message = nil
      thread = Thread.current
      once :message do |msg|
        message = msg
        thread.wakeup
      end
      yield
      sleep response_timeout
      message
    end

    def start_reading_data
      @data_thread = Thread.new do
        @driver.on :message, ->(e) { emit :message, e.data }
        @driver.on :error, ->(e) { emit :error, e.message }
        loop do
          begin
            data = @socket.readpartial RECV_BUFFER_SIZE unless @socket.closed?
            @driver.parse data unless @socket.closed?
          rescue StandardError
            break
          end
        end
      end
    end

    def create_socket(host, port, timeout = 20)
      begin
        address = Resolv.getaddress(host)
      rescue Resolv::ResolvError
        raise ConnectionError, "Hostname not known: #{host}"
      end
      ip_addr = IPAddr.new address
      family = ip_addr.family

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
        @socket
      rescue Errno::ECONNREFUSED
        raise ConnectionError, "Connection refused for [#{ip_addr}]:#{port} "
      end
    end

    def select_timeout(type, timeout)
      if timeout >= 0
        type == :read ? read_array = [@socket] : write_array = [@socket]
        IO.select(read_array, write_array, [@socket], timeout) && return
      end
      raise ConnectionError, 'Connection timeout'
    end

    def process_headers(headers)
      headers.each do |k, v|
        @driver.set_header(k, v)
      end
    end
  end
end
