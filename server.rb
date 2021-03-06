require 'digest/sha1'
require 'socket'

class Node < Struct.new(:id, :ip, :port)
end

class Server

  attr_reader :successor, :predecessor, :finger, :max_nodes

  def id
    return @this_node.id
  end

  def initialize(host, port, cb, args)
    # constructor
    @cb = cb
    @args = args
    @host = host
    # 16-bit id
    @port = port.to_i
    @id_bit_len = 16
    @max_nodes = 1 << @id_bit_len # or 2 ** (@id_bit_len)

    set_new_id
    @this_node = Node.new(@id, @host, @port)
    @finger = []

    create_ring
    run_server
  end

  def set_new_id
    hex = Digest::SHA1.hexdigest "#{@host}#{@port}"
    @id = hex[0...(@id_bit_len / 4)].to_i 16
    # Using consistent hasing SHA-1
  end

  def is_in_open_interval(x, lower, upper)
    # checking if x is in (lower, upper)
    if lower == upper && x != lower
      return true
    end
    if lower < upper
      if x > lower && x < upper
        return true
      end
    else
      if x > lower || x < upper
        return true
      end
    end
    return false
  end

  def ask_for_successor(tcps, id)
    # request: find successor
    tcps.puts "find_succ #{id}"
    msg = tcps.gets.chomp.split
    return Node.new(msg[0].to_i, msg[1], msg[2].to_i) 
  end

  def ask_for_predecessor(tcps)
    # request: find predecessor
    tcps.puts "find_pred"
    msg = tcps.gets.chomp.split
    if msg[0] == "nil"
      return nil
    else
      return Node.new(msg[0].to_i, msg[1], msg[2].to_i) 
    end
  end

  def find_successor(id)
    # find the successor by ID
    # if id is in (n, successor]
    if (id == @successor.id ||
        is_in_open_interval(id, @this_node.id, @successor.id))
      return @successor
    else
      next_node = closest_preceding_node(id)
      tcps = TCPSocket.open(next_node.ip, next_node.port)
      node = ask_for_successor(tcps, id)
      tcps.close
      return node
    end
  end

  def closest_preceding_node(id)
    # find the closest preceding node by given ID
    i = @id_bit_len-1
    until i == 0 do
      # if finger[i] is in (n, id)
      if is_in_open_interval(@finger[i].id, @this_node.id, id)
        return @finger[i]
      end
      i = i-1
    end
    return @this_node
  end

  def create_ring
    # initialize the ring
    @predecessor = nil
    @successor = @this_node
    (0..@id_bit_len-1).each { |i| @finger[i] = @this_node }
  end

  def join(ip, port)
    # join a new chat by given (ip, port)
    tcps = TCPSocket.open(ip, port.to_i)
    @successor = ask_for_successor(tcps, @this_node.id)
    tcps.close
  end

  def stabilize
    # fix the successor
    tcps = TCPSocket.open(@successor.ip, @successor.port)
    node = ask_for_predecessor(tcps)
    tcps.close
    if !node.nil?
      if is_in_open_interval(node.id, @this_node.id, @successor.id) # if node is in (n, successor)
        @successor = node
      end
    end
    # notify successor
    tcps = TCPSocket.open(@successor.ip, @successor.port)
    tcps.puts "notify #{@this_node.id} #{@this_node.ip} #{@this_node.port}"
    tcps.close
  end

  def notified(node)
    # if this node is notified then update the predecessor
    if @predecessor.nil? || is_in_open_interval(node.id, @predecessor.id, @this_node.id)
      @predecessor = node
    end
  end

  def fix_fingers
    # update the finger table periodically
    (0..@id_bit_len - 1).each do |i|
      id = (@this_node.id + 2**i) % @max_nodes
      @finger[i] = find_successor(id)
    end
  end

  def leave
    # notify the successor and predecessor before leaving
    tcps = TCPSocket.open(@predecessor.ip, @predecessor.port)
    tcps.puts "succ_leave #{@successor.id} #{@successor.ip} #{@successor.port}"
    tcps.close
    tcps = TCPSocket.open(@successor.ip, @successor.port)
    tcps.puts "pred_leave"
    tcps.close
  end

=begin
  def check_predecessor
    if (predecessor has failed)
      predecessor = nil;
    end
  end
=end

  def start
    # do stabilize and fix_fingers periodically
    Thread.new do
      loop do
        stabilize
        fix_fingers
        sleep(1)
      end
    end
  end

  def run_server
    # run the server and wait for connections
    @tcp_server = TCPServer.open(@host, @port)
    Thread.new do
      loop do
        Thread.start(@tcp_server.accept) do |client|
          instruction = client.gets.chomp.split
          case instruction[0]
          when "find_succ"
            node = find_successor(instruction[1].to_i)
            client.puts "#{node.id} #{node.ip} #{node.port}"
          when "find_pred"
            if @predecessor.nil?
              client.puts "nil"
            else
              client.puts "#{@predecessor.id} #{@predecessor.ip} #{@predecessor.port}"
            end
          when "notify"
            node = Node.new(instruction[1].to_i, instruction[2], instruction[3].to_i)
            notified(node)
          when "succ_leave"
            node = Node.new(instruction[1].to_i, instruction[2], instruction[3].to_i)
            @successor = node
          when "pred_leave"
            @predecessor = nil
          when "msg"
            sender_id = instruction[1].to_i
            msg = client.gets.chomp
            if sender_id != @this_node.id
              @cb.call sender_id, msg, @args # output the message
              send_msg_to_succ msg, sender_id
            end
          end
          client.close
        end
      end
    end
  end

  def send_msg_to_succ(msg, sender_id)
    # send message to successor
    tcps = TCPSocket.open(@successor.ip, @successor.port)
    tcps.puts "msg #{sender_id}"
    tcps.puts msg
    tcps.close
  end

  def send_msg(msg)
    # send message(source) to successor
    send_msg_to_succ(msg, @this_node.id) 
  end
end
