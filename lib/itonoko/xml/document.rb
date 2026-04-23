# frozen_string_literal: true

module Itonoko
  module XML
    class Document < Node
      attr_accessor :encoding, :version, :errors

      def initialize
        super(DOCUMENT_NODE, "#document", nil)
        @document = self
        @encoding = "UTF-8"
        @version  = "1.0"
        @errors   = []
      end

      def self.parse(string, url = nil, encoding = nil, options = nil, &block)
        require_relative "../parser/xml_parser"
        Parser::XmlParser.new.parse(string.to_s)
      end

      def root
        children.find { |c| c.node_type == ELEMENT_NODE }
      end

      def root=(node)
        old_root = root
        old_root&.remove
        add_child(node)
      end

      def create_element(name, content = nil)
        node = Node.new(ELEMENT_NODE, name, self)
        node.add_child(Text.new(content, self)) if content
        node
      end

      def create_text_node(content)
        Text.new(content, self)
      end

      def create_comment(content)
        Comment.new(content, self)
      end

      def create_cdata(content)
        CDATA.new(content, self)
      end

      def text
        root&.text.to_s
      end

      def to_xml(options = {})
        decl  = %(<?xml version="#{version}" encoding="#{encoding}"?>\n)
        decl + children.map { |c| c.to_xml(options) }.join
      end

      def to_html
        children.map(&:to_html).join
      end

      def to_s
        to_xml
      end

      def xpath(expr, namespaces = {})
        require_relative "../xpath/evaluator"
        XPath::Evaluator.new(self, namespaces).evaluate(expr)
      end

      def css(selector)
        require_relative "../css/matcher"
        CSS::Matcher.match(self, selector)
      end

      def collect_namespaces
        {}
      end

      def doc
        self
      end
    end
  end
end
