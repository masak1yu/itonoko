# frozen_string_literal: true

module Itonoko
  module HTML
    class DocumentFragment < XML::Node
      def initialize(document = nil)
        super(XML::Node::DOCUMENT_FRAGMENT_NODE, "#document-fragment", document)
      end

      def self.parse(markup, document = nil)
        require_relative "../parser/html_parser"
        frag = new(document)
        doc  = Parser::HtmlParser.new.parse("<_itonoko_frag>#{markup}</_itonoko_frag>")
        wrapper = doc.root || doc.children.first
        source = wrapper&.name == "_itonoko_frag" ? wrapper.children : (doc.children)
        source.each { |c| frag.add_child(c) }
        frag
      end

      def to_html
        children.map(&:to_html).join
      end

      def to_s
        to_html
      end
    end
  end
end
