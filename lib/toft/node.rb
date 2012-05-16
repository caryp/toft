require 'observer'
require 'net/ssh'
require 'ping'
require 'toft/file_checker'
require 'toft/command_executor'

module Toft
  
  class Node
    PRIVATE_KEY = <<-EOF
-----BEGIN RSA PRIVATE KEY-----
MIIEpAIBAAKCAQEAwoLge1y9wEcy2WC7CDGXuFFDt+9Zvh+QulfDIbZkpYF7YBw6
O3mYTUpucwnqMhnd9jini8bsQghJF3wwxdWmtmurcHAEhN6ZljXZwUu2rojh+D+4
PnkOAMPb+w3REmyFYBxfzQ4gBBRXZgKWDTN6Al9hYRFTVSsZJCKJFK+GsWBSc5ie
l6IuUnfCbTwvORWVV6g7nGQ5x0JTnApG0qNFDprFkBsLbvHlB6A3lBtHQfJ7W/cZ
QXi3LXawD4bhWAl/CHxZHXGpJM7+tREz2yhOoPcHUwwv0xHqe/wBxmJmq84kZ8Co
lTi9Y5xNXKDiS6svMDgt3ShpkWcvQ+LE3PhUVQIDAQABAoIBAQCEvfZemeLw9mXw
TYA2TknhQqw5OYIAKuCFGuGS/ztea6f75iejcQ8MKDCKF4kZGegNYYqN7HpNcgQX
n+xVBsJYGdCM0hVza8pa5XMu4/HO2KGF3k5pbAmvYfqdMUeuEBtRhOuoL+yPfCZM
+pTWe3vXZKo7KSy6ocftjhgI4uTD5OtUHZe+Q61K8Ng5723kk4KcbZo4LHEvj4C2
nnplt9uxiS04qTPuJohxiwE1pbSybaH5Kndfvzmh1A1q/HKCZNhQKK/jhgvDBtBu
hiDfPtKdEeSTbFm11ckJBE1HPdAXoppxwDHQzcq82+vNJdB2P2TsMPklPRb6FuDa
dCQ0B5IBAoGBAPUlki+Q6yC4snhJ7r0ipIiMimB+Q6UlrE6ayyc3s/akjvTaqs2z
tcZTPUVVLjs0WIRIYwOWMcNmMZoi2s8nGsDiljmd1+smWHPK8A9X8pSUH6Z5k7sS
fzno3ytRXohyR2UB6iuUoT3F0VEnaaDjLlNk77DYusAmMsrm8W5PkMHVAoGBAMsf
aocc8yrwC7Wa0xfeNreK4F3OayqP6xAu0aSXqj1gtJ6HTTgY2g4jqtnV40NVXwHK
7zA4ie5IfmQ/672Te+9ifeWYNqv8faHDJwZFbZ2LwPW/lm5i4Ezn9KMmpLTz+6yj
f1bS+Y0NYyxfs1nn7Lx/kvuJVdIV+Ktma+ZHGAiBAoGAHo6NV0KAHHcJP/cvPAIa
ci7afMagVfCJNs8SrZPC6eZ/L0QmcDeLW+o6Q+8nMRgIRIzlUqghEdMmMalQjuu3
6P0Vbp8fL996vQw5uh/jS+Pewhh7cqEOnMBLORIOb4GXJp8DemUvaAzFV5FLGFPZ
DWoSen+5X4QjZqk8xNxEFfUCgYB+xR6xMMo69BH6x6QTc2Zm6s/Y++k6aRPlx7Kj
rNxc7iwL/Jme9zOwO2Z4CduKvI9NCSB60e6Tvr7TRmmUqaVh4/B7CKKmeDDYcnm6
mj4tY3mMZoQ2ZJNkrCesY4PMQ7HBL1FcGNQSylYo7Zl79Rl1E5HiVvYu5fOK1aNl
1t0TAQKBgQCaN91JXWJFXc1rJsDy365SKrX00Nt8rZolFQy2UhhERoCxD0uwbOYm
sfWYRr79L2BZkyRHmuxCD24SvHibDev+T0Jh6leXjnrwd/dj3P0tH8+ctET5SXsD
CQWv13UgQjiHgQILXSb7xdzpWK1wpDoqIEWQugRyPQDeZhPWVbB4Lg==
-----END RSA PRIVATE KEY-----    
    EOF
    
    TIMEOUT_IN_SECONDS = 120
    TRY_INTERVAL = 0.5
    
    include Observable
    include Toft::CommandExecutor

    def initialize(hostname, options = {})
      options = {:ip => DYNAMIC_IP, :netmask => "24", :type => "natty"}.merge(options)
      @hostname = hostname
      @ip = options[:ip]
      @netmask = options[:netmask]
      unless exists?
        create(hostname, options)
      end
      @chef_runner = Toft::Chef::ChefRunner.new("#{rootfs}") do |chef_command|
        run_ssh chef_command
      end

      @puppet_runner = options[:runner]
      @puppet_runner ||= Toft::Puppet::PuppetRunner.new("#{rootfs}") do |puppet_command|
        run_ssh puppet_command
      end
    end
    
    def hostname
      return @hostname
    end
    
    def create(hostname, options)
      raise "not implemented"
    end
    
    def exists?
      raise "not implemented"
    end

    def start
      puts "Starting host node..."
      vm_start
      wait_ssh_ready
    end

    def stop
      raise "not implemented"
    end

    def destroy
      stop
      vm_destroy
      changed
      notify_observers(@hostname)
    end
    
    def running?
      raise "not implemented"
    end
    
    def add_cname(cname)
      run_ssh "echo -e 'update add #{cname}.#{Toft::DOMAIN} 86400 CNAME #{@hostname}.#{Toft::DOMAIN}\\nsend' | nsupdate"
    end
    
    def remove_cname(cname)
      run_ssh "echo -e 'update delete #{cname}.#{Toft::DOMAIN}\\nsend' | nsupdate"      
    end

    def run_ssh(command)
      raise ArgumentError, "Trying to run empty command on node #{@hostname}", caller if command.blank?
      stdout = ""
      stderr = ""
      Net::SSH.start(fqdn, "root", :key_data => [PRIVATE_KEY], :paranoid => false) do |ssh|
        ssh.open_channel do |channel|
          channel.exec(command) do |ch, success|
            raise RuntimeError, "Could not execute command: [#{command}]", caller unless success

            channel.on_data do |c, data|
              puts data
              stdout << data
              yield data if block_given?
            end
            channel.on_extended_data do |c, type, data|
              puts data
              stderr << data
              yield data if block_given?
            end
            channel.on_request("exit-status") do |c, data|
              exit_code = data.read_long
              raise CommandExecutionError.new "Remote command [#{command}] exited with status #{exit_code}", stdout, stderr unless exit_code.zero?
            end
            channel.on_request("exit-signal") do |c, data|
              raise CommandExecutionError.new "Remote command [#{command}] terminated with signal", stdout, stderr
            end
          end
        end.wait
      end
      return CommandResult.new stdout, stderr
    end
    
    def rm(dir)
      raise ArgumentError, "Illegal dir path: [#{dir}]", caller if dir.blank? || dir[0] != ?/
      cmd! "rm -rf #{rootfs}#{dir}"
    end

    def run_chef(run_list, params = {})
      @chef_runner.run run_list, params
    end

    def run_puppet(run_list, params = {})
      @puppet_runner.run run_list, params
    end

    def file(path)
      FileChecker.new(rootfs, path)
    end
    
    def ip
      @ip == Toft::DYNAMIC_IP ? `dig +short #{fqdn}`.strip : @ip
    end

    private
    def rootfs
      "/var/lib/lxc/#{@hostname}/rootfs"
    end
    
    def wait_sshd_running
      raise "not implemented"
    end    
    
    def wait_remote_host_reachable
      wait_for do
        begin
          return if Ping.pingecho fqdn, 0.1
        rescue Exception
          # fix the strange pingcho exception
        end
      end
      raise RuntimeError, "Remote machine not responding." if try >= max_try
    end

    def wait_for
      return if !block_given?
      max_try = TIMEOUT_IN_SECONDS / TRY_INTERVAL
      try = 0
      while try < max_try
        output_progress
        yield
        sleep TRY_INTERVAL
        try += 1        
      end
    end

    def output_progress
      print "."
      STDOUT.flush
    end

    def wait_ssh_ready
      print "Waiting for host sshd ready"
      wait_sshd_running
      print "\nWaiting for host to be reachable"
      wait_remote_host_reachable
      puts "\nSSH connection on '#{@hostname}/#{@ip}' is ready."
    end
    
    def fqdn
      "#{@hostname}.#{Toft::DOMAIN}"
    end


    # Create correct node for our virtualization environment
    # === Returns
    # clazz(Class): a node class defined in node directory
    def self.factory
      eval("Toft::#{virtualization}Node")
    end

    # Try to decern if we are setup for Linux Containers or KVM
    # === Returns
    # type(Symbol): virtualization type (i.e :LXC or :KVM)
    def self.virtualization
      type = :LXC # Linux Containers is default

      if File.exists?("/proc/modules")
        modules = File.read("/proc/modules")
        if modules =~ /^kvm/
          type = :KVM
        end
      end
      
      if File.exists?("/proc/cpuinfo")
        if File.read("/proc/cpuinfo") =~ /QEMU Virtual CPU/
          type = :KVM
        end
      end
      type
    end
    
  end
  
  class CommandResult
    attr_reader :stdout, :stderr
    
    def initialize(stdout, stderr)
      @stdout = stdout
      @stderr = stderr
    end
  end

  class CommandExecutionError < RuntimeError
    attr_reader :message, :stdout, :stderr
    
    def initialize(message, stdout, stderr)
      @message = message
      @stdout = stdout
      @stderr = stderr
    end
  end
end
