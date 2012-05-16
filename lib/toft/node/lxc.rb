require 'toft/node'

module Toft
  module Node
    class LXC < Node
    
      def create(hostname, options)
        cmd! "lxc-create -n #{hostname} -f #{generate_lxc_config} -t #{options[:type].to_s}"
      end

      def exists?
        cmd("lxc-ls") =~ /#{@hostname}/
      end
    
      def vm_start
        cmd "lxc-start -n #{@hostname} -d" # system + sudo lxc-start does not work on centos-6, but back-quote does(no clue on why)
        cmd! "lxc-wait -n #{@hostname} -s RUNNING"
      end
    
      def stop
        cmd! "lxc-stop -n #{@hostname}"
        cmd! "lxc-wait -n #{@hostname} -s STOPPED"
      end

      def vm_destroy
          cmd! "lxc-destroy -n #{@hostname}"
      end
    
      def running?
        cmd("lxc-info -n #{@hostname}") =~ /RUNNING/
      end
    
      def wait_sshd_running
        wait_for do
          netstat = cmd("lxc-netstat --name #{@hostname} -ta")        
          return if netstat =~ /ssh/
        end
      end
    
      private
    
      def generate_lxc_config
        full_ip = @ip == Toft::DYNAMIC_IP ? "#{@ip}" : "#{@ip}/#{@netmask}"
        conf = <<-EOF
  lxc.network.type = veth
  lxc.network.flags = up
  lxc.network.link = br0
  lxc.network.name = eth0
  lxc.network.ipv4 = #{full_ip}
        EOF
        conf_file = "/tmp/#{@hostname}-conf"
        File.open(conf_file, 'w') do |f|
          f.write(conf);
        end
        return conf_file
      end
      
    end
  end
end
