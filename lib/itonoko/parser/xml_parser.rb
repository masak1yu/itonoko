# frozen_string_literal: true

require "strscan"
require_relative "entities"
require_relative "../xml/node"
require_relative "../xml/text"
require_relative "../xml/node_set"
require_relative "../xml/document"
require_relative "../xml/document_fragment"

module Itonoko
  module Parser
    class XmlParser
      def parse(xml)
        @doc        = XML::Document.new
        @doc.errors = []
        @open_stack = [@doc]
        @buf        = +""
        tokenize_and_build(StringScanner.new(xml.to_s))
        @doc
      end

      private

      def tokenize_and_build(sc)
        until sc.eos?
          if sc.scan(/<!--/)
            flush_buf
            comment = scan_until(sc, /-->/)
            @open_stack.last.append_child(XML::Comment.new(comment, @doc))

          elsif sc.scan(/<!\[CDATA\[/)
            flush_buf
            cdata = scan_until(sc, /\]\]>/)
            @open_stack.last.append_child(XML::CDATA.new(cdata, @doc))

          elsif sc.scan(/<\?xml\s/i)
            sc.scan(/[^?]*/)
            sc.scan(/\?>/)

          elsif sc.scan(/<\?/)
            target  = sc.scan(/[^\s?]+/) || ""
            sc.scan(/\s*/)
            content = scan_until(sc, /\?>/)
            @open_stack.last.append_child(XML::ProcessingInstruction.new(target, content, @doc))

          elsif sc.scan(/<!DOCTYPE/i)
            sc.scan(/[^>]*/)
            sc.scan(/>/)

          elsif sc.scan(/<\//)
            flush_buf
            name = sc.scan(/[^\s>\/]+/) || ""
            sc.scan(/[^>]*/)
            sc.scan(/>/)
            handle_end_tag(name)

          elsif sc.scan(/</) && sc.check(/[a-zA-Z_]|[^\x00-\x7F]/)
            flush_buf
            name  = sc.scan(/[^\s>\/]+/) || ""
            attrs = {}
            scan_attributes(sc, attrs)
            self_closing = sc.scan(/\//) ? true : false
            sc.scan(/>/)
            handle_start_tag(name, attrs, self_closing)

          elsif (chunk = sc.scan(/[^<]+/))
            @buf << chunk
          else
            @buf << sc.getch
          end
        end
        flush_buf
      end

      def scan_until(sc, pattern)
        content = +""
        until sc.eos?
          break if sc.scan(pattern)
          content << sc.getch
        end
        content
      end

      def scan_attributes(sc, attrs)
        loop do
          sc.scan(/\s+/)
          break if sc.eos? || sc.check(/[>\/]/)
          attr_name = sc.scan(/[^\s=>\/"':]+/) or break
          sc.scan(/\s*/)
          if sc.scan(/=/)
            sc.scan(/\s*/)
            val = if sc.scan(/"/)
              v = sc.scan(/[^"]*/) || ""
              sc.scan(/"/)
              v
            elsif sc.scan(/'/)
              v = sc.scan(/[^']*/) || ""
              sc.scan(/'/)
              v
            else
              sc.scan(/[^\s>]+/) || ""
            end
            attrs[attr_name] = decode_entities(val)
          else
            attrs[attr_name] = attr_name
          end
        end
      end

      def flush_buf
        return if @buf.empty?
        text = decode_entities(@buf)
        @open_stack.last.append_child(XML::Text.new(text, @doc)) unless text.empty?
        @buf.clear
      end

      def decode_entities(str)
        return str.dup unless str.include?("&")
        str.gsub(/&([^;\s]{1,10});/) { Parser.decode_entity($1) }
      end

      def handle_start_tag(name, attrs, self_closing)
        node = XML::Node.new(XML::Node::ELEMENT_NODE, name, @doc)
        attrs.each { |k, v| node[k] = v }
        @open_stack.last.append_child(node)
        @open_stack.push(node) unless self_closing
      end

      def handle_end_tag(name)
        idx = @open_stack.rindex { |n| n.node_name == name }
        @open_stack.slice!(idx..) if idx && idx > 0
      end
    end
  end
end
