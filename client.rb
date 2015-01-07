require 'socket'
require 'json'
require './server'

class Client

  class << self

    def receive_message(sender_id, data, cli)
      json = JSON.parse data
      puts "#{json['name']}> #{json['msg']}"
    end
  end

  def initialize(host, port)
    # constructor
    callback = Client.method(:receive_message)
    @server = Server.new host, port.to_i, callback, self
    @alive = true
  end

  def start
    # ask user to join a chat
    print "Join a chat(y/n)? "
    cmd = $stdin.gets.chomp
    if cmd == 'y'
      print "IP: "
      ip = $stdin.gets.chomp
      print "port: "
      port = $stdin.gets.chomp
      @server.join ip, port
    end
    @server.start

    # start the chat
    print "Enter the username: "
    @name = $stdin.gets.chomp
    @server.send_msg "#{@name} join the chat."
    puts "================================"
    puts "Welcome to the p2p chat room!"
    puts "================================"

    listen
  end

  def listen
    # listen stdin
    while @alive do
      msg = $stdin.gets.chomp
      cmd = msg.split
      case cmd[0]
      when "/table"
        list_table
      when "/exit"
      	@server.leave
      	@alive = false
      else
        @server.send_msg JSON[name: @name, msg: msg]
      end
    end
  end

  def list_table
    # check successor, predecessor and finger table
  	id = @server.get_my_id
    succ = @server.get_successor
    pred = @server.get_predecessor
    fingers = @server.get_fingers

    puts "------------------"
    puts "id: #{id}"
    puts "successor: #{succ}"
    puts "predecessor: #{pred}"
    fingers.each { |x| puts x }
    puts "------------------"
  end

end

ip = ARGV[0]
port = ARGV[1].to_i
p2p_client = Client.new ip, port
p2p_client.start
