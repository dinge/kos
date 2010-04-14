# require 'active_support/dependencies'

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
    Neo4j::ref_node.koslet_hubs
    # @kos_instance.initializer.hub_nodes
    # or Neo4j::ref_node.koslet_hubs
  end




  class Runner
    attr_reader :initializer

    def initialize
      @initializer = Initializer.new
    end
  end


  class Initializer

    KosletsPath = "app/kos/" # there will be later more of those, also for better code sharing and distribution

    def initialize
      add_kos_root_to_load_paths
      extend_reference_node
      @koslet_modules = load_koslets
      post_process_koslet_modules
      @hub_nodes = []
    end

    def add_kos_root_to_load_paths
      # ActiveSupport::Dependencies.load_paths << File.expand_path('app')
      $LOAD_PATH << File.expand_path('app')
    end

    def load_koslets
      Dir['%s/*/*.rb' % File.expand_path(KosletsPath)].map do |koslet_file|
        file_basename = File.basename(koslet_file, '.rb')
        if file_basename == File.dirname(koslet_file).match(/^.*\/kos\/([\w]+)$/)[1] # only load module root
          # ActiveSupport::Dependencies.require_or_load(koslet_file)
          load(koslet_file)
          koslet_module = ('Kos::%s' % file_basename.classify).constantize
          koslet_module.instance_variable_set(:@koslet_file, koslet_file)
          koslet_module
        end
      end.compact
    end

    def koslets
      @koslet_modules
    end

    def hub_nodes
      @koslet_modules.map { |koslet| koslet.hub_node }
    end

    def post_process_koslet_modules
      @koslet_modules.each do |koslet_module|
        koslet_module.extend(ActiveSupport::Autoload)
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
        lib_path = Pathname.new( File.dirname(koslet_file) ).join('lib').to_s
        # ActiveSupport::Dependencies.load_paths.unshift(lib_path)
        $LOAD_PATH.unshift(lib_path)
        extend ActiveSupport::Autoload

        Dir['%s/*.rb' % lib_path].each do |lib_file|
          part = File.basename(lib_file, '.rb')
          class_eval do
            autoload part.classify.to_sym, lib_file
          end
        end
      end

      def init_koslet_hub_node
        unless @hub_node = Neo4j.ref_node.koslet_hubs.find { |node| node[:name] == name }
          Neo4j.ref_node.koslet_hubs << (@hub_node = Kos::Koslet::HubNode.new(:name => name))
        end
        extend KosletHubClassExtension
      end

    end



    class HubNode
      include Neo4j::NodeMixin
      has_one   :reference_node
      property  :name
      index     :name
    end
  end




  module ReferenceNodeClassExtension
    def self.included(base)
      base.has_n :koslet_hubs
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
