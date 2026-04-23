# frozen_string_literal: true

module Itonoko
  module XML
    class NodeSet
      include Enumerable

      attr_reader :document

      def initialize(document, nodes = [])
        @document = document
        @nodes    = nodes.to_a
      end

      def length
        @nodes.length
      end
      alias size length
      alias count length

      def empty?
        @nodes.empty?
      end

      def [](index)
        @nodes[index]
      end

      def first(n = nil)
        n ? @nodes.first(n) : @nodes.first
      end

      def last(n = nil)
        n ? @nodes.last(n) : @nodes.last
      end

      def push(node)
        @nodes.push(node)
        self
      end
      alias << push

      def each(&block)
        @nodes.each(&block)
      end

      def +(other)
        seen = {}
        combined = (@nodes + other.to_a).each_with_object([]) do |n, arr|
          unless seen[n.object_id]
            seen[n.object_id] = true
            arr << n
          end
        end
        NodeSet.new(document, combined)
      end
      alias | +

      def -(other)
        other_ids = other.to_a.map(&:object_id).to_set
        NodeSet.new(document, @nodes.reject { |n| other_ids.include?(n.object_id) })
      end

      def &(other)
        other_ids = other.to_a.map(&:object_id).to_set
        NodeSet.new(document, @nodes.select { |n| other_ids.include?(n.object_id) })
      end

      def css(selector)
        NodeSet.new(document, flat_map { |n| n.css(selector).to_a })
      end

      def xpath(expr, namespaces = {})
        NodeSet.new(document, flat_map { |n| n.xpath(expr, namespaces).to_a })
      end

      def at_css(selector)
        each do |n|
          result = n.at_css(selector)
          return result if result
        end
        nil
      end

      def at_xpath(expr, namespaces = {})
        each do |n|
          result = n.at_xpath(expr, namespaces)
          return result if result
        end
        nil
      end

      def text
        map(&:text).join
      end
      alias inner_text text

      def to_html
        map(&:to_html).join
      end
      alias to_s to_html

      def to_xml(options = {})
        map { |n| n.to_xml(options) }.join
      end

      def inner_html
        map(&:inner_html).join
      end

      def remove
        each(&:remove)
        self
      end
      alias unlink remove

      def wrap(markup)
        each { |node| node.wrap(markup) }
        self
      end

      def attr(name)
        first&.[](name)
      end

      def attribute(name)
        first&.attribute(name)
      end

      def to_a
        @nodes.dup
      end

      def inspect
        "#<#{self.class} [#{@nodes.map(&:inspect).join(', ')}]>"
      end
    end
  end
end
