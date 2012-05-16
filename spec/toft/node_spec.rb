require 'spec_helper'

describe "Node" do

  describe 'run_puppet' do

    it 'should run block with puppet runner' do
      puppet_runner = mock Toft::Puppet::PuppetRunner.class
      puppet_runner.should_receive(:run).with('manifest', {})
      
      node = Toft::Node::Node.factory().new("my_host", {:runner => puppet_runner})
      node.run_puppet('manifest')

    end

  end

  it 'should support LXC' do
    Toft::Node::Node.stub(:virtualization).and_return(:LXC)
    Toft::Node::Node.stub(:exists?).and_return(true)
    node = Toft::Node::Node.factory().new("my_host")
    node.class.name.should == "Toft::Node::LXC"
  end

  it 'should support KVM' do
    Toft::Node::Node.stub(:virtualization).and_return(:KVM)
    Toft::Node::Node.stub(:exists?).and_return(true)
    node = Toft::Node::Node.factory().new("my_host")
    node.class.name.should == "Toft::Node::KVM"
 end

end

