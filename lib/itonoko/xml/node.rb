# frozen_string_literal: true

require "cgi/escape"

module Itonoko
  module XML
    class Node
      ELEMENT_NODE                = 1
      ATTRIBUTE_NODE              = 2
      TEXT_NODE                   = 3
      CDATA_SECTION_NODE          = 4
      PROCESSING_INSTRUCTION_NODE = 7
      COMMENT_NODE                = 8
      DOCUMENT_NODE               = 9
      DOCUMENT_TYPE_NODE          = 10
      DOCUMENT_FRAGMENT_NODE      = 11

      # Shared frozen constants — leaf nodes use these to avoid per-node allocation.
      EMPTY_ATTRS    = {}.freeze
      EMPTY_CHILDREN = [].freeze

      attr_accessor :parent, :document
      attr_reader   :node_type, :node_name, :children

      def initialize(node_type, node_name, document = nil)
        @node_type  = node_type
        @node_name  = node_name
        @document   = document
        @parent     = nil
        @children   = []
        @attributes = EMPTY_ATTRS  # upgraded to mutable hash on first write
      end

      # ── navigation ────────────────────────────────────────────────

      def root
        return self if parent.nil? || parent.node_type == DOCUMENT_NODE
        parent.root
      end

      def next_sibling
        return nil unless parent
        idx = parent.children.index(self)
        idx && parent.children[idx + 1]
      end

      def previous_sibling
        return nil unless parent
        idx = parent.children.index(self)
        idx && idx > 0 ? parent.children[idx - 1] : nil
      end

      def next_element
        sib = next_sibling
        sib = sib.next_sibling while sib && sib.node_type != ELEMENT_NODE
        sib
      end

      def previous_element
        sib = previous_sibling
        sib = sib.previous_sibling while sib && sib.node_type != ELEMENT_NODE
        sib
      end

      def ancestors(selector = nil)
        result = []
        node = parent
        while node
          result << node if node.node_type != DOCUMENT_NODE
          node = node.parent
        end
        list = NodeSet.new(document, result)
        selector ? list.select { |n| n.matches_css?(selector) } : list
      end

      def element_children
        NodeSet.new(document, children.select { |c| c.node_type == ELEMENT_NODE })
      end

      def child
        children.first
      end

      # ── attributes ────────────────────────────────────────────────

      def name
        node_name
      end

      def [](attr_name)
        @attributes[attr_name.to_s]
      end

      def []=(attr_name, value)
        if @attributes.frozen?
          @attributes = { attr_name.to_s => value.to_s }
        else
          @attributes[attr_name.to_s] = value.to_s
        end
      end

      def get_attribute(name)
        @attributes[name.to_s]
      end

      def set_attribute(name, value)
        self[name] = value
      end

      def remove_attribute(name)
        return if @attributes.frozen?
        @attributes.delete(name.to_s)
      end

      def has_attribute?(name)
        @attributes.key?(name.to_s)
      end

      def keys
        @attributes.keys
      end

      def attribute(name)
        val = @attributes[name.to_s]
        return nil unless val
        Attr.new(name.to_s, val, document)
      end

      def attributes
        @attributes.each_with_object({}) do |(k, v), h|
          a = Attr.new(k, v, document)
          h[k] = a
        end
      end

      def attribute_nodes
        @attributes.map { |k, v| Attr.new(k, v, document) }
      end

      # ── content ───────────────────────────────────────────────────

      # Accumulator-based text extraction — avoids intermediate arrays and join.
      def text
        buf = +""
        _collect_text(buf)
        buf
      end
      alias content text
      alias inner_text text

      # Override in subclasses for leaf nodes.
      def _collect_text(buf)
        @children.each { |c| c._collect_text(buf) }
      end

      def text=(str)
        @children = [Text.new(str.to_s, document).tap { |t| t.parent = self }]
      end
      alias content= text=

      # ── fast path for parsers (skips parent-removal + coercion) ───

      def append_child(node)
        node.parent   = self
        node.document = @document
        @children << node
        node
      end

      # ── tree manipulation ─────────────────────────────────────────

      def add_child(node_or_markup)
        nodes = coerce_nodes(node_or_markup)
        nodes.each do |node|
          node.parent&.children&.delete(node)
          node.parent   = self
          node.document = document
          @children << node
        end
        nodes.length == 1 ? nodes.first : NodeSet.new(document, nodes)
      end
      alias << add_child

      def prepend_child(node_or_markup)
        nodes = coerce_nodes(node_or_markup)
        nodes.reverse_each do |node|
          node.parent&.children&.delete(node)
          node.parent   = self
          node.document = document
          @children.unshift(node)
        end
        nodes.length == 1 ? nodes.first : NodeSet.new(document, nodes)
      end

      def add_next_sibling(node_or_markup)
        raise "no parent" unless parent
        nodes = coerce_nodes(node_or_markup)
        idx   = parent.children.index(self) + 1
        nodes.each_with_index do |node, i|
          node.parent&.children&.delete(node)
          node.parent   = parent
          node.document = document
          parent.children.insert(idx + i, node)
        end
        nodes.length == 1 ? nodes.first : NodeSet.new(document, nodes)
      end
      alias after add_next_sibling

      def add_previous_sibling(node_or_markup)
        raise "no parent" unless parent
        nodes = coerce_nodes(node_or_markup)
        idx   = parent.children.index(self)
        nodes.each_with_index do |node, i|
          node.parent&.children&.delete(node)
          node.parent   = parent
          node.document = document
          parent.children.insert(idx + i, node)
        end
        nodes.length == 1 ? nodes.first : NodeSet.new(document, nodes)
      end
      alias before add_previous_sibling

      def remove
        parent&.children&.delete(self)
        @parent = nil
        self
      end
      alias unlink remove

      def replace(node_or_markup)
        raise "no parent" unless parent
        nodes = coerce_nodes(node_or_markup)
        idx   = parent.children.index(self)
        parent.children.delete_at(idx)
        nodes.reverse_each do |node|
          node.parent   = parent
          node.document = document
          parent.children.insert(idx, node)
        end
        @parent = nil
        nodes.length == 1 ? nodes.first : NodeSet.new(document, nodes)
      end

      def inner_html=(markup)
        @children = []
        frag = document.is_a?(HTML::Document) ?
               HTML::DocumentFragment.parse(markup, document) :
               XML::DocumentFragment.parse(markup, document)
        frag.children.each { |c| add_child(c) }
      end

      # ── search ────────────────────────────────────────────────────

      def css(selector)
        require_relative "../css/matcher"
        CSS::Matcher.match(self, selector)
      end

      def xpath(expr, namespaces = {})
        require_relative "../xpath/evaluator"
        XPath::Evaluator.new(self, namespaces).evaluate(expr)
      end

      def at_css(selector)
        css(selector).first
      end

      def at_xpath(expr, namespaces = {})
        xpath(expr, namespaces).first
      end

      def search(*queries)
        NodeSet.new(document, queries.flat_map { |q| css(q).to_a })
      end

      def at(*queries)
        search(*queries).first
      end

      def matches?(selector)
        CSS::Matcher.matches_selector?(self, selector)
      end

      # ── serialization ─────────────────────────────────────────────

      # String concat instead of map+join — one less intermediate Array.
      def inner_html
        buf = +""
        @children.each { |c| buf << c.to_html }
        buf
      end

      def to_html
        html_mode = document.nil? || document.is_a?(HTML::Document)
        case node_type
        when ELEMENT_NODE
          serialize_element(html_mode)
        when TEXT_NODE, CDATA_SECTION_NODE
          escape_text(node_name)
        when COMMENT_NODE
          "<!--#{node_name}-->"
        when PROCESSING_INSTRUCTION_NODE
          "<?#{node_name}?>"
        when DOCUMENT_NODE, DOCUMENT_FRAGMENT_NODE
          inner_html
        else
          ""
        end
      end

      def to_xml(options = {})
        case node_type
        when ELEMENT_NODE
          serialize_element(false)
        when TEXT_NODE
          escape_text(node_name)
        when CDATA_SECTION_NODE
          "<![CDATA[#{node_name}]]>"
        when COMMENT_NODE
          "<!--#{node_name}-->"
        when PROCESSING_INSTRUCTION_NODE
          "<?#{node_name}?>"
        when DOCUMENT_NODE, DOCUMENT_FRAGMENT_NODE
          buf = +""
          @children.each { |c| buf << c.to_xml(options) }
          buf
        else
          ""
        end
      end

      def to_s
        to_html
      end

      def inspect
        "#<#{self.class} name=#{node_name.inspect} children=#{children.length}>"
      end

      def ==(other)
        equal?(other)
      end

      def element?
        node_type == ELEMENT_NODE
      end

      def text?
        node_type == TEXT_NODE
      end

      def comment?
        node_type == COMMENT_NODE
      end

      def cdata_node?
        node_type == CDATA_SECTION_NODE
      end

      def fragment?
        node_type == DOCUMENT_FRAGMENT_NODE
      end

      def document?
        node_type == DOCUMENT_NODE
      end

      def description
        node_name
      end

      private

      VOID_ELEMENTS = %w[
        area base br col embed hr img input link meta param source track wbr
      ].freeze

      def serialize_element(html_mode)
        tag      = node_name
        attr_str = serialize_attributes
        open_tag = "<#{tag}#{attr_str}>"

        if html_mode && VOID_ELEMENTS.include?(tag.downcase)
          return open_tag
        end

        if @children.empty?
          return html_mode ? "#{open_tag}</#{tag}>" : "<#{tag}#{attr_str}/>"
        end

        "#{open_tag}#{inner_html}</#{tag}>"
      end

      def serialize_attributes
        return "" if @attributes.empty?
        buf = +""
        @attributes.each { |k, v| buf << %( #{k}="#{escape_attr(v)}") }
        buf
      end

      # CGI.escapeHTML is a C implementation — fastest available escape.
      def escape_text(str)
        CGI.escapeHTML(str.to_s)
      end

      def escape_attr(str)
        CGI.escapeHTML(str.to_s)
      end

      def coerce_nodes(node_or_markup)
        case node_or_markup
        when Node
          [node_or_markup]
        when NodeSet
          node_or_markup.to_a
        when String
          frag = document.is_a?(HTML::Document) ?
                 HTML::DocumentFragment.parse(node_or_markup, document) :
                 XML::DocumentFragment.parse(node_or_markup, document)
          frag.children.dup
        else
          [node_or_markup]
        end
      end
    end
  end
end
