require "socket"
require "./server"

class Client

  def initialize(host, port)
    # constructor
    @server = Server.new host, port.to_i
    @alive = true
  end

  def start()
    # ask user to join a chat
    puts "Join a chat(y/n)?"
    cmd = $stdin.gets.chomp
    if cmd == 'y'
      puts "IP:"
      ip = $stdin.gets.chomp
      puts "port:"
      port = $stdin.gets.chomp
      @server.join ip, port
    end
    @server.start

    # start the chat
    puts "Enter the username:"
    @name = $stdin.gets.chomp
    @server.send_msg "#{@name} join the chat."
    puts "================================"
    puts "Welcome to the p2p chat room!"
    puts "================================"

    listen
  end

  def listen()
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
        @server.send_msg "#{@name}> #{msg}"
      end
    end
  end

  def list_table()
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
