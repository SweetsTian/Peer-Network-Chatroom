require 'socket'
require 'thread'
require 'json'

Node_InetAddr = Struct.new(:ip, :port)
$gateway_InetAddr = Node_InetAddr.new('127.0.0.1',2000)
Node = Struct.new(:id,:Node_InetAddr)
$limit_min = [48,331352,662656,993959,1325262] # To limit the route set of node id
$limit_max = [331351,662655,993958,1325261,1656564]

class Gateway
  class << self

    def gateway_init
      @all_nodes = Hash.new
      @server = TCPServer.new 2000
      @work_q = Queue.new

      puts "Gateway start..."
      self.node_listener
      self.worker

    end

    def node_listener

      Thread.new {
        loop do
          #puts "open listener"
          @work_q.push @server.accept # add request to the queue
        end

      }
    end

    def worker
      workers = (0...4).map do
        Thread.new do
          loop do
            while !@work_q.empty?
              client = @work_q.pop
              #puts "hahahah"
              data = client.gets

              data = JSON.parse data # parse data to hash format
              case data["type"]
                when "JOINING NETWORK" then

                  #puts "JOINING NETWORK"
                  if add_node(data["node_ip"],data["node_port"],data["node_id"])

                    puts "#{data["node_id"]} join the network"
                   # puts @all_nodes
                    return_result = get_routeTable data["node_id"]
                    client.puts return_result.to_json
                  else
                    client.puts false
                  end
                when "LEAVE NETWORK" then
                  node_id = data["node_id"]
                  @all_nodes.delete(node_id)
                  puts "#{node_id} leave the network"
                  client.puts true
              end
              # 50.times{print [128000+x].pack "U*"}
            end
          end
        end
      end
      workers.map(&:join)
    end

    def add_node(node_ip,node_port,node_id)
      if !@all_nodes.has_key?(node_id)
        @all_nodes.store(node_id,Node_InetAddr.new(node_ip,node_port))
        return true
      else
        return false
      end
    end

    def init_routeTable()
      t = Hash.new

      for i in 1..4
        for j in 1..7
          t["#{j},#{i}"] = nil
        end
      end

      t
    end

    def get_routeTable(node_id)
      #node_route_table is initiate with nil
      node_route_table = init_routeTable
      temp_array = Array.new(8)
      #get leaf set by search all node record in the gateway node
      @all_nodes.each_key {|key|
        # when key(the node_id in the @all_nodes) smaller than the node_id given by the node need to get the route table
        # The key node will compare with the leaf set which is smaller than the node_id
        if key<node_id
          # There are four node in the leaf set which is smaller than the node_id
          for i in 1..4
            if node_route_table.fetch("1,#{i}")==nil # if the node is nil then replace the node with with key node
              node_route_table["1,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
              temp_array[i-1]=key
              break
            else # then compare
              node = node_route_table.fetch("1,#{i}")
             # puts node.values[0]
              if node.values[0]<key
                j = 4
                while j>i
                  node_route_table["1,#{j}"] = node_route_table["1,#{j-1}"] # every node in the node_route_table move one before the i
                  temp_array[j-1] = temp_array[j-2]
                  j=j-1
                end
                node_route_table["1,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                temp_array[i-1]=key
                break
              end
            end
          end
        elsif key>node_id && !temp_array.include?(key)
          for i in 1..4
            if node_route_table.fetch("2,#{i}")==nil # if the node is nil then replace the node with with key node
              node_route_table["2,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
              temp_array[i+3] = key
              break
            else # then compare
              node = node_route_table.fetch("2,#{i}")
              if node.values[0]>key
                j = 4
                while j>i
                  node_route_table["2,#{j}"] = node_route_table["2,#{j-1}"] # every node in the node_route_table move one before the i
                  temp_array[j+3]=temp_array[j+3-1]
                  j=j-1
                end
                node_route_table["2,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                temp_array[i+3]=key
                break
              end
            end
          end

        end

      }

      #get the route node of the route table
      @all_nodes.each_key{|key|

        if !temp_array.include?(key) && key!=node_id
          case key
            when $limit_min[0]..$limit_max[0]
              # the first row in the route table
              for i in 1..4
                if node_route_table.fetch("3,#{i}")==nil # if the node is nil then replace the node with with key node
                  node_route_table["3,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
                  break
                else # then compare
                  node = node_route_table.fetch("3,#{i}")

                  if node.values[0]<key
                    j = 4
                    while j>i
                      node_route_table["3,#{j}"] = node_route_table["3,#{j-1}"] # every node in the node_route_table move one before the i
                      j=j-1
                    end
                    node_route_table["3,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                    break
                  end
                end
              end
            when $limit_min[1]..$limit_max[1]
              # the first row in the route table
              for i in 1..4
                if node_route_table.fetch("4,#{i}")==nil # if the node is nil then replace the node with with key node
                  node_route_table["4,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
                  break
                else # then compare
                  node = node_route_table.fetch("4,#{i}")
                  if node.values[0]<key
                    j = 4
                    while j>i
                      node_route_table["4,#{j}"] = node_route_table["4,#{j-1}"] # every node in the node_route_table move one before the i
                      j=j-1
                    end
                    node_route_table["4,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                    break
                  end
                end
              end
            when $limit_min[2]..$limit_max[2]
              # the first row in the route table
              for i in 1..4
                if node_route_table.fetch("5,#{i}")==nil # if the node is nil then replace the node with with key node
                  node_route_table["5,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
                  break
                else # then compare
                  node = node_route_table.fetch("5,#{i}")
                  if node.values[0]<key
                    j = 4
                    while j>i
                      node_route_table["5,#{j}"] = node_route_table["5,#{j-1}"] # every node in the node_route_table move one before the i
                      j=j-1
                    end
                    node_route_table["5,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                    break
                  end
                end
              end
            when $limit_min[3]..$limit_max[3]
              # the first row in the route table
              for i in 1..4
                if node_route_table.fetch("6,#{i}")==nil # if the node is nil then replace the node with with key node
                  node_route_table["6,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
                  break
                else # then compare
                  node = node_route_table.fetch("6,#{i}")
                  if node.values[0]<key
                    j = 4
                    while j>i
                      node_route_table["6,#{j}"] = node_route_table["6,#{j-1}"] # every node in the node_route_table move one before the i
                      j=j-1
                    end
                    node_route_table["6,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                    break
                  end
                end
              end
            else
              # the first last in the route table
              for i in 1..4
                if node_route_table.fetch("7,#{i}")==nil # if the node is nil then replace the node with with key node
                  node_route_table["7,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]}
                  break
                else # then compare
                  node = node_route_table.fetch("7,#{i}")
                  if node.values[0]<key
                    j = 4
                    while j>i
                      node_route_table["7,#{j}"] = node_route_table["7,#{j-1}"] # every node in the node_route_table move one before the i
                      j=j-1
                    end
                    node_route_table["7,#{i}"]= {"id"=>key,"ip"=>@all_nodes.fetch(key).values[0],"port"=>@all_nodes.fetch(key).values[1]} # put the new node to the Hash table
                    break
                  end
                end
              end

          end

        end
      }

      node_route_table
    end

  end
end

Gateway.gateway_init