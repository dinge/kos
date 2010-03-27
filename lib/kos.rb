module Kos

  def self.instance
    Runner.new
  end

  def self.io=(kos_instance)
    @kos_instance = kos_instance
  end

  def Kos.io(giznode = nil)
    @kos_instance
  end

  def self.koslets
    @kos_instance.initializer.koslets
  end

  def self.hub_nodes
    @kos_instance.initializer.hub_nodes
  end




  class Runner
    attr_reader :initializer

    def initialize
      @initializer = Initializer.new
    end
  end


  class Initializer

    CosletsPath = "app/kos/" # there will be later more of those, also for better code sharing and distribution

    def initialize
      extend_reference_node
      @koslet_modules = load_koslets
      post_process_koslet_modules
      @hub_nodes = []
    end

    def load_koslets
      Dir['%s/*/*.rb' % File.expand_path(CosletsPath)].map do |koslet_file|
        require koslet_file
        koslet_module = ('Kos::%s' % File.basename(koslet_file, '.rb').classify).constantize
        koslet_module.instance_variable_set(:@koslet_file, koslet_file)
        koslet_module
      end
    end

    def koslets
      @koslet_modules
    end

    def hub_nodes
      @koslet_modules.map { |koslet| koslet.hub_node }
    end

    def post_process_koslet_modules
      @koslet_modules.each do |koslet_module|
        koslet_module.extend(Koslet::KosletExtensions)
      end
      @koslet_modules.each do |koslet_module|
        koslet_module.init_without_engine
      end

      Neo4j::Transaction.run do
        @koslet_modules.each do |koslet_module|
          koslet_module.init_koslet_hub_node
        end
      end
    end

    def extend_reference_node
      Neo4j::ReferenceNode.send(:include, ReferenceNodeClassExtension)
    end

  end



  module Koslet

    module KosletExtensions

      def koslet_file
        @koslet_file
      end

      def hub_node
        @hub_node
      end

      def init_without_engine
        return if const_defined?('Engine')
        lib_path = File.join(File.dirname(koslet_file), 'lib')
        $LOAD_PATH.unshift(lib_path)

        Dir['%s/*.rb' % lib_path].each do |lib_file|
          module_eval do
            part = File.basename(lib_file, '.rb')
            autoload part.classify.to_sym, part
          end
        end
      end

      def init_koslet_hub_node
        unless hub_node = Neo4j.ref_node.koslet_hubs.find { |node| node[:name] == name }
          Neo4j.ref_node.koslet_hubs << (hub_node = Kos::Koslet::HubNode.new(:name => name))
        end
        @hub_node = hub_node
        extend(KosletHubClassExtension)
      end

    end



    class HubNode
      include Neo4j::NodeMixin
      has_one(:reference_node)
      property :name
    end
  end




  module ReferenceNodeClassExtension
    def self.included(base)
      base.has_n(:koslet_hubs)
    end
  end



  module KosletHubClassExtension
    def hub_node
      @hub_node
    end
  end

end

Kos.io = Kos.instance

p Kos.io
