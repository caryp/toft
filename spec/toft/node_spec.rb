require 'spec_helper'

describe "Node" do

  describe 'run_puppet' do

    it 'should run block with puppet runner' do
      puppet_runner = mock Toft::Puppet::PuppetRunner.class
      puppet_runner.should_receive(:run).with('manifest', {})
      
      node = Toft::Node.factory().new("my_host", {:runner => puppet_runner})
      node.run_puppet('manifest')

    end

  end
  
  it 'should support Linux Containers' do
    Toft::Node.stub(:virtualization).and_return(:LXC)
    node = Toft::Node.factory().new("my_host")
    node.class.name.should == "Toft::LXCNode"
  end
  
  it 'should support KVM' do
    Toft::Node.stub(:virtualization).and_return(:KVM)
    node = Toft::Node.factory().new("my_host")
    node.class.name.should == "Toft::KVMNode"
  end

end
