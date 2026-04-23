# frozen_string_literal: true

module Itonoko
  module XML
    class DocumentFragment < Node
      def initialize(document = nil)
        super(DOCUMENT_FRAGMENT_NODE, "#document-fragment", document)
      end

      def self.parse(markup, document = nil)
        require_relative "../parser/xml_parser"
        frag = new(document)
        doc  = Parser::XmlParser.new.parse("<_root>#{markup}</_root>")
        doc.root.children.each { |c| frag.add_child(c) }
        frag
      end

      def to_html
        children.map(&:to_html).join
      end

      def to_xml(options = {})
        children.map { |c| c.to_xml(options) }.join
      end

      def to_s
        to_html
      end
    end
  end
end
