require 'socket'
require 'json'
require 'thread'

$gateway_InetAddr = {"ip"=>'127.0.0.01',"port"=>8080}
$limit_min = [48,331352,662656,993959,1325262] # To limit the route set of node id
$limit_max = [331351,662655,993958,1325261,1656564]

class Peer
  def initialize
    @route_table = Hash.new
    @socket = nil

    @work_q = nil
    @node_ip = nil
    @node_id = nil
    @chat_record = Hash.new


  end

  def init(port)

    @work_q = Queue.new
    @node_port=port
    @node_ip = getIp
    @socket = UDPSocket.new
    @socket.bind(nil,@node_port)

    self.user_input
    self.node_listener()
    self.worker

  end

  def getIp
    ip = UDPSocket.open {|s| s.connect("64.233.187.99", 1); s.addr.last}
    ip
  end

  def node_listener
    Thread.new{
      loop do
        data, sender = @socket.recvfrom(65536)
        data = JSON.parse data # parse data to hash format
        @work_q.push data # add request to the queue
        # puts data
      end
    }
  end

  def worker
    workers = (0...4).map do
      Thread.new do

        loop do
          while !@work_q.empty?
            msg = @work_q.pop(true)
            #puts msg
            # handle the message get from other peers
            if msg["target_node_id"] == @node_id
              handle_msg msg
            else
              #puts "test"
              found_node_id,is_in_leaf_set = search_node_in_route_table msg["target_node_id"], msg["is_in_leaf_set"]
              if found_node_id==nil # if return nil shows that is no node in the route table or on close node than this node
                #puts "no more node is match than me"
                handle_msg msg
              else
                if is_in_leaf_set
                  msg["is_in_leaf_set"]=true
                end
                #puts @route_table.fetch(found_node_id)["ip"],@route_table.fetch(found_node_id)["port"]
                send_udp_msg msg, @route_table.fetch(found_node_id)["ip"],@route_table.fetch(found_node_id)["port"] # pass the msg to the next node
              end

            end
          end
        end
      end
    end
    workers.map(&:join)
  end

  def handle_msg(msg)

    case msg["type"]

      when "CHAT" then
        tag = msg["tag"]
        text = msg["text"]
        if @chat_record.has_key? tag # if this node already has this tag save the text
          @chat_record.fetch(tag) << text
        else # if the node did not have this tag, add a new tag and save teh text
          @chat_record.store(tag,[text])
        end
        if sender_id = msg["sender_id"]==@node_id
          puts "Get \"CHAT\" message from node #{msg["sender_id"]}, tag is #{msg["tag"]},text is #{msg["text"]}"
          puts "Get \"CHAT  RESPONSE\" from node #{@node_id} is #{@chat_record.fetch(tag)}"
        else
          #sender_node = Node_InetAddr.new()
          #puts "send response message:"
          response_msg = {"type"=>"CHAT RESPONSE","tag"=>tag,"target_node_id"=>msg["sender_id"],"text"=>@chat_record.fetch(tag),"sender_id"=>@node_id,"sender_ip"=>@node_ip,"sender_port"=>@node_port}
          send_udp_msg response_msg,msg["sender_ip"],msg["sender_port"]
        end

      when "CHAT RESPONSE" then
        puts "************************************************************\nGet the chat response from the node #{msg["sender_id"]}. \nThe tag is #{msg["tag"]}. \nAnd the chat text is \n#{msg["text"]}\n************************************************************"
      when "ROUTE INFO" then

    end
  end

  def leave_network
    puts "#{@node_id} leaving the network please wait......"
    msg = {"type"=>"LEAVE NETWORK","node_id"=>@node_id,"node_ip"=>@node_ip,"node_port"=>@node_port}
    #puts msg
    result = send_msg_to_gateway msg
    if result == false
      puts "Leave network fail, please try again!"
    else #result is the route_table
      puts "Leave network successful! Close the client...."
      exit
      #puts @route_table.fetch("1,1")
    end
  end

  def send_msg_to_gateway(msg)
    socket_to_gateway = TCPSocket.new 'localhost', 2000
    #socket_to_gateway = TCPSocket.new $gateway_InetAddr["id"],$gateway_InetAddr.values[1]

   # puts msg.to_json
    socket_to_gateway.puts msg.to_json
    return_msg = socket_to_gateway.gets # read lines form the gateway
    #puts return_msg
    socket_to_gateway.close

    return_msg
  end

  def send_udp_msg(msg,ip,port)
    #receiver_port = inetAddr["port"]
    receiver_ip = ip
    receiver_port =port
    #puts receiver_port
    #puts receiver_ip

    #puts msg

      @socket.send(msg.to_json, 0, 'localhost', receiver_port)
    #puts "already send message"
      #text, sender = s.recvfrom(254)
    #puts "get response"
     # remote_host = sender[3]
     # puts "#{remote_host}:#{receiver_port} responsed #{text}"


    #s.send(msg,0,receiver_ip,receiver_port)
    #text,sender = s.recvfrom(65536) # get response from the server
    #remote_host = sender[3]
    #puts "#{remote_host}:#{receiver_port} responsed #{text}"
  end

  def join_network()
    today = Time.new
    time = today.strftime("%M%S")
    @node_id = HashCode(time.to_s)
    puts "#{@node_id} joining the network,please wait...."
    msg = {"type"=>"JOINING NETWORK","node_id"=>@node_id,"node_ip"=>@node_ip,"node_port"=>@node_port}
    #puts msg
    result = send_msg_to_gateway msg
    if result == false
      puts "Join network fail, please try again!"
    else #result is the route_table
      puts "Join network successful!"
      @route_table = JSON.parse result
      puts "The route table of the node is #{@route_table}"
      #puts @route_table.fetch("1,1")

    end
  end

  def chat(tag, text)
    target_id = HashCode tag
    route_node,is_in_leaf_set = search_node_in_route_table target_id,false
    msg = {"type"=>"CHAT","tag"=>tag,"target_node_id"=>target_id,"is_in_leaf_set"=>is_in_leaf_set,"text"=>text,"sender_id"=>@node_id,"sender_ip"=>@node_ip,"sender_port"=>@node_port}
    #puts "Route Path #{route_node["id"]}"
    if  route_node.equal?(nil)
      #puts "null"
      handle_msg msg
    elsif route_node["id"]==@node_id

      handle_msg msg
    else
      node = @route_table.fetch(route_node)
      #puts node
      #puts node["ip"]
      #puts node["port"]
      #puts "haaaa"
      send_udp_msg msg,node["ip"],node["port"]
    end
  end

  def user_input
    Thread.new{
      loop do
        puts "\nIf you want join the network please input \"JOINING NETWORK\" .If you want leave the network please input \"LEAVE NETWORK\".If you want chat please input \"CHAT\"."
        user_wants = gets.chomp
        user_wants = user_wants.to_s
        #puts user_wants
        case user_wants
          when "CHAT" then
            if !@node_id.equal?(nil)
              puts "Please type tag"
              tag = gets.chomp
              puts "Please type text"
              text = gets.chomp
              chat tag,text
            else
              puts "Please join the network before chat!"
            end

          when "JOINING NETWORK" then
            #puts "Please type port"
            #@node_port = gets.chomp.to_i
            self.join_network
          when "LEAVE NETWORK" then
            if @node_id.equal?(nil)
              puts "The node did not join the network, please join the network before leave!"
            else
              self.leave_network
            end

          else
            puts "Wrong input, please input again!"
        end
      end

    }
  end

  def search_node_in_route_table(target_node_id,is_in_leaf_set)
    temp_node = nil # to record the node which is closet to the target node
    temp_gap = (target_node_id-@node_id).abs # to record the numerical gap closet to the target node
    #puts "temp_gap: #{temp_gap}"
    #puts "target_node _id #{target_node_id}"
    temp_leaf_set = is_in_leaf_set
    if target_node_id < @node_id # search in the leaf set to find the target node
      #puts "test1"
      for i in 1..4
        if @route_table.has_key?("1,#{i}")
          if !@route_table.fetch("1,#{i}").equal?(nil)
            if @route_table.fetch("1,#{i}")["id"].to_i==target_node_id
              temp_node = "1,#{i}"
              temp_leaf_set = true
              break
            elsif (@route_table.fetch("1,#{i}")["id"].to_i-target_node_id).abs < temp_gap
              temp_node = "1,#{i}"
              temp_gap = (@route_table.fetch("1,#{i}")["id"].to_i - target_node_id).abs
              temp_leaf_set = true
       #       puts "temp_gap test2: #{temp_gap}"
            end
          end

        end

      end
    elsif target_node_id>@node_id
      #puts "TTTTTTTTTest"
      for i in 1..4
       # puts "test xunhuan #{i}"
        if @route_table.has_key?("2,#{i}")
          if !@route_table.fetch("2,#{i}").equal?(nil)
            if @route_table.fetch("2,#{i}")["id"].to_i==target_node_id
              temp_node = "2,#{i}"
              return temp_node,true
            elsif (@route_table.fetch("2,#{i}")["id"].to_i-target_node_id).abs < temp_gap
              temp_node = "2,#{i}"
              temp_gap = (@route_table.fetch("2,#{i}")["id"].to_i - target_node_id).abs
              temp_leaf_set = true
        #      puts "temp_gap test2: #{temp_gap}"
            end
          end

        end

      end
    end

    #puts "temp in leaf set? #{temp_leaf_set}"
    if !temp_leaf_set # search in the route set to find the target node
      case target_node_id
        when $limit_min[0]..$limit_max[0]
          for i in 1..4
            if @route_table.has_key?("3,#{i}")
              if !@route_table.fetch("3,#{i}").equal?(nil)
                if @route_table.fetch("3,#{i}")["id"].to_i==target_node_id
                  temp_node = "3,#{i}"
                  return temp_node,true

                elsif (@route_table.fetch("3,#{i}")["id"].to_i-target_node_id).abs < temp_gap
                  temp_node = "3,#{i}"
                  temp_gap = (@route_table.fetch("3,#{i}")["id"].to_i - target_node_id).abs
                end
              end
            end
          end
        when $limit_min[1]..$limit_max[1]
          for i in 1..4
            if @route_table.has_key?("4,#{i}")
              if !@route_table.fetch("4,#{i}").equal?(nil)
                if @route_table.fetch("4,#{i}")["id"].to_i==target_node_id
                  temp_node = "4,#{i}"
                  return temp_node,true
                elsif (@route_table.fetch("4,#{i}")["id"].to_i-target_node_id).abs < temp_gap
                  temp_node = "4,#{i}"
                  temp_gap = (@route_table.fetch("4,#{i}")["id"].to_i - target_node_id).abs
                end
              end
            end
          end
        when $limit_min[2]..$limit_max[2]
          for i in 1..4
            if @route_table.has_key?("5,#{i}")
              if !@route_table.fetch("5,#{i}").equal?(nil)
                if @route_table.fetch("5,#{i}")["id"].to_i==target_node_id
                  temp_node = "5,#{i}"
                  return temp_node,true
                elsif (@route_table.fetch("5,#{i}")["id"].to_i-target_node_id).abs < temp_gap
                  temp_node = "5,#{i}"
                  temp_gap = (@route_table.fetch("5,#{i}")["id"].to_i - target_node_id).abs
                end
              end
            end
          end
        when $limit_min[3]..$limit_max[3]
          for i in 1..4
            if @route_table.has_key?("6,#{i}")
              if !@route_table.fetch("6,#{i}").equal?(nil)
                if @route_table.fetch("6,#{i}")["id"].to_i==target_node_id
                  temp_node = "6,#{i}"
                  return temp_node,true
                elsif (@route_table.fetch("6,#{i}")["id"].to_i-target_node_id).abs < temp_gap
                  temp_node = "6,#{i}"
                  temp_gap = (@route_table.fetch("6,#{i}")["id"].to_i - target_node_id).abs
                end
              end
            end
          end
        else
      #    puts "Test else"
          for i in 1..4
       #     puts "Else xunhuan #{i}"
            if @route_table.has_key?("7,#{i}")
              if !@route_table.fetch("7,#{i}").equal?(nil)
                if @route_table.fetch("7,#{i}")["id"].to_i==target_node_id
                  temp_node = "7,#{i}"
                  return temp_node,true
                elsif (@route_table.fetch("7,#{i}")["id"].to_i-target_node_id).abs < temp_gap
                  temp_node = "7,#{i}"
                  temp_gap = (@route_table.fetch("7,#{i}")["id"].to_i - target_node_id).abs
                end
              end
            end
          end
      end
    end
    #puts "before return test"
    #puts temp_node, temp_leaf_set
    return temp_node,temp_leaf_set # return node found in the route table and if it is found in the leaf set
  end


  def HashCode(word)
    #Generates a hash of a word that is passed. mainly used for generation of a nodeID
    word = word.split('')              #Separates word into individual characters for ASCII value conversion
    hash=0                             #initialises the hash value
    b=0                                #initialises array counter
    word.each do |i|
      if word[b].nil?                  #For the case of creating the first node where it has no target_ID
        hash=0
      else
        hash =hash *31 + word[b].ord   #Otherwise compute the hash from ASCII converted word
      end
      b=b+1                            #Increment counter
    end

    hash.abs                             #Return the result of the HashCode
  end


end


peer = Peer.new
puts "Please input the port of peer:"
port = gets.chomp.to_i
peer.init port
