# frozen_string_literal: true

module Itonoko
  module XML
    class Attr
      attr_accessor :name, :value, :document

      ATTRIBUTE_NODE = 2

      def initialize(name, value, document = nil)
        @name     = name
        @value    = value
        @document = document
      end

      def node_name
        @name
      end

      def node_type
        ATTRIBUTE_NODE
      end

      def to_s
        value.to_s
      end

      def inspect
        "#<#{self.class} name=#{name.inspect} value=#{value.inspect}>"
      end
    end
  end
end
