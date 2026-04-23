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
        @doc = XML::Document.new
        @doc.errors = []
        scanner = StringScanner.new(xml.to_s)
        @open_stack = [@doc]
        tokenize(scanner)
        @doc
      end

      private

      def tokenize(scanner)
        buf = +""

        until scanner.eos?
          if scanner.scan(/<!--/)
            flush_text(buf)
            buf = +""
            comment = +""
            until scanner.eos?
              if scanner.scan(/-->/)
                break
              else
                comment << scanner.getch
              end
            end
            @open_stack.last.add_child(XML::Comment.new(comment, @doc))

          elsif scanner.scan(/<!\[CDATA\[/)
            flush_text(buf)
            buf = +""
            cdata = +""
            until scanner.eos?
              if scanner.scan(/\]\]>/)
                break
              else
                cdata << scanner.getch
              end
            end
            @open_stack.last.add_child(XML::CDATA.new(cdata, @doc))

          elsif scanner.scan(/<\?xml\s/i)
            scanner.scan(/[^?]*/)
            scanner.scan(/\?>/)

          elsif scanner.scan(/<\?/)
            target = scanner.scan(/[^\s?]+/) || ""
            scanner.scan(/\s*/)
            content = +""
            until scanner.eos?
              if scanner.scan(/\?>/)
                break
              else
                content << scanner.getch
              end
            end
            @open_stack.last.add_child(XML::ProcessingInstruction.new(target, content, @doc))

          elsif scanner.scan(/<!DOCTYPE/i)
            scanner.scan(/[^>]*/)
            scanner.scan(/>/)

          elsif scanner.scan(/<\//)
            flush_text(buf)
            buf = +""
            name = scanner.scan(/[^\s>\/]+/) || ""
            scanner.scan(/[^>]*/)
            scanner.scan(/>/)
            handle_end_tag(name)

          elsif scanner.scan(/</)
            if scanner.check(/[a-zA-Z_]|[^\x00-\x7F]/)
              flush_text(buf)
              buf = +""
              name = scanner.scan(/[^\s>\/]+/) || ""
              attrs = {}
              parse_attributes(scanner, attrs)
              self_closing = !scanner.scan(/\//).nil?
              scanner.scan(/>/)
              handle_start_tag(name, attrs, self_closing)
            else
              buf << "<"
            end

          else
            buf << scanner.getch
          end
        end

        flush_text(buf)
      end

      def parse_attributes(scanner, attrs)
        loop do
          scanner.scan(/\s+/)
          break if scanner.eos? || scanner.check(/[>\/]/)

          attr_name = scanner.scan(/[^\s=>\/"':]+/)
          break unless attr_name

          scanner.scan(/\s*/)
          if scanner.scan(/=/)
            scanner.scan(/\s*/)
            if scanner.scan(/"/)
              val = scanner.scan(/[^"]*/)
              scanner.scan(/"/)
              attrs[attr_name] = decode_entities(val || "")
            elsif scanner.scan(/'/)
              val = scanner.scan(/[^']*/)
              scanner.scan(/'/)
              attrs[attr_name] = decode_entities(val || "")
            else
              val = scanner.scan(/[^\s>]+/) || ""
              attrs[attr_name] = decode_entities(val)
            end
          else
            attrs[attr_name] = attr_name
          end
        end
      end

      def flush_text(buf)
        return if buf.empty?
        text = decode_entities(buf)
        @open_stack.last.add_child(XML::Text.new(text, @doc)) unless text.empty?
        buf.clear
      end

      def decode_entities(str)
        str.gsub(/&([^;\s]{1,10});/) { Parser.decode_entity($1) }
      end

      def handle_start_tag(name, attrs, self_closing)
        node = XML::Node.new(XML::Node::ELEMENT_NODE, name, @doc)
        attrs.each { |k, v| node[k] = v }
        @open_stack.last.add_child(node)
        @open_stack.push(node) unless self_closing
      end

      def handle_end_tag(name)
        idx = @open_stack.rindex { |n| n.node_name == name }
        return unless idx && idx > 0
        @open_stack.slice!(idx..)
      end
    end
  end
end
