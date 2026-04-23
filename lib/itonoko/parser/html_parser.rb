# frozen_string_literal: true

require "strscan"
require_relative "entities"
require_relative "../xml/node"
require_relative "../xml/text"
require_relative "../xml/node_set"
require_relative "../xml/document"
require_relative "../html/document"

module Itonoko
  module Parser
    class HtmlParser
      VOID_ELEMENTS = %w[
        area base br col embed hr img input link meta param source track wbr
      ].to_set.freeze

      RAW_TEXT_ELEMENTS = %w[script style].to_set.freeze

      # Elements that auto-close a previous open same/related element
      AUTO_CLOSE = {
        "p"  => %w[p],
        "li" => %w[li],
        "dt" => %w[dt dd],
        "dd" => %w[dd dt],
        "td" => %w[td th],
        "th" => %w[td th],
        "tr" => %w[tr],
        "colgroup" => %w[colgroup],
        "caption"  => %w[caption],
        "option"   => %w[option],
        "optgroup" => %w[optgroup option],
        "rb"  => %w[rb rt rtc rp],
        "rt"  => %w[rb rt rp],
        "rp"  => %w[rb rt rtc rp],
        "rtc" => %w[rb rtc rp],
      }.freeze

      # Implied end tags for implicit closing
      IMPLIED_END_CLOSED_BY = {
        "li" => %w[ul ol],
        "dt" => %w[dl],
        "dd" => %w[dl],
        "tr" => %w[table tbody thead tfoot],
        "td" => %w[tr table tbody thead tfoot],
        "th" => %w[tr table tbody thead tfoot],
        "colgroup" => %w[table],
        "caption"  => %w[table],
      }.freeze

      Token = Struct.new(:type, :name, :attrs, :self_closing, :data, keyword_init: true)

      def parse(html)
        @doc = HTML::Document.new
        @doc.errors = []
        tokens = tokenize(html)
        build_tree(tokens)
        @doc
      end

      private

      # ── Tokenizer ────────────────────────────────────────────────

      def tokenize(html)
        scanner = StringScanner.new(html.to_s)
        tokens  = []
        buf     = +""

        until scanner.eos?
          if scanner.scan(/<!--/)
            flush_text(tokens, buf)
            buf = +""
            comment = +""
            until scanner.eos?
              if scanner.scan(/--!?>/)
                break
              elsif scanner.scan(/-->/)
                break
              else
                comment << scanner.getch
              end
            end
            tokens << Token.new(type: :comment, data: comment)

          elsif scanner.scan(/<!\[CDATA\[/)
            flush_text(tokens, buf)
            buf = +""
            cdata = +""
            until scanner.eos?
              if scanner.scan(/\]\]>/)
                break
              else
                cdata << scanner.getch
              end
            end
            tokens << Token.new(type: :cdata, data: cdata)

          elsif scanner.scan(/<!DOCTYPE/i)
            flush_text(tokens, buf)
            buf = +""
            scanner.scan(/[^>]*/)
            scanner.scan(/>/)
            tokens << Token.new(type: :doctype)

          elsif scanner.scan(/<\//)
            flush_text(tokens, buf)
            buf = +""
            name = scanner.scan(/[^\s>\/]+/) || ""
            scanner.scan(/[^>]*/)
            scanner.scan(/>/)
            tokens << Token.new(type: :end_tag, name: name.downcase)

          elsif scanner.scan(/</)
            # Check if it's a valid start tag
            if scanner.check(/[a-zA-Z_!]/)
              flush_text(tokens, buf)
              buf = +""
              name = scanner.scan(/[^\s>\/]+/) || ""
              name = name.downcase
              attrs = {}
              self_closing = false

              # Raw text elements: consume everything until closing tag
              if RAW_TEXT_ELEMENTS.include?(name)
                # Parse attributes first
                parse_attributes(scanner, attrs)
                self_closing = scanner.scan(/\//)
                scanner.scan(/>/)
                tokens << Token.new(type: :start_tag, name: name, attrs: attrs, self_closing: self_closing)
                unless self_closing
                  raw = +""
                  end_pattern = /<\/#{Regexp.escape(name)}\s*>/i
                  until scanner.eos?
                    if scanner.check(end_pattern)
                      break
                    else
                      raw << scanner.getch
                    end
                  end
                  tokens << Token.new(type: :characters, data: raw) unless raw.empty?
                  if scanner.scan(end_pattern)
                    tokens << Token.new(type: :end_tag, name: name)
                  end
                end
              else
                parse_attributes(scanner, attrs)
                self_closing = !scanner.scan(/\//).nil?
                scanner.scan(/>/)
                tokens << Token.new(type: :start_tag, name: name, attrs: attrs, self_closing: self_closing)
              end
            else
              buf << "<"
            end

          else
            buf << scanner.getch
          end
        end

        flush_text(tokens, buf)
        tokens
      end

      def parse_attributes(scanner, attrs)
        loop do
          scanner.scan(/\s+/)
          break if scanner.eos? || scanner.check(/[>\/]/)

          attr_name = scanner.scan(/[^\s=>\/"']+/)
          break unless attr_name

          scanner.scan(/\s*/)
          if scanner.scan(/=/)
            scanner.scan(/\s*/)
            if scanner.scan(/"/)
              val = scanner.scan(/[^"]*/)
              scanner.scan(/"/)
              attrs[attr_name.downcase] = decode_entities(val || "")
            elsif scanner.scan(/'/)
              val = scanner.scan(/[^']*/)
              scanner.scan(/'/)
              attrs[attr_name.downcase] = decode_entities(val || "")
            else
              val = scanner.scan(/[^\s>]+/) || ""
              attrs[attr_name.downcase] = decode_entities(val)
            end
          else
            attrs[attr_name.downcase] = attr_name.downcase
          end
        end
      end

      def flush_text(tokens, buf)
        return if buf.empty?
        text = decode_entities(buf)
        tokens << Token.new(type: :characters, data: text)
        buf.clear
      end

      def decode_entities(str)
        str.gsub(/&([^;\s]{1,10});/) { Parser.decode_entity($1) }
      end

      # ── Tree Builder ─────────────────────────────────────────────

      def build_tree(tokens)
        @open_stack = [@doc]

        tokens.each do |token|
          case token.type
          when :doctype
            # ignore, already have an HTML document

          when :start_tag
            handle_start_tag(token)

          when :end_tag
            handle_end_tag(token)

          when :characters
            current = @open_stack.last
            # Skip pure whitespace outside any non-document node when stack is just @doc
            if @open_stack.length == 1 && token.data.strip.empty?
              next
            end
            text_node = XML::Text.new(token.data, @doc)
            current.add_child(text_node)

          when :comment
            current = @open_stack.last
            comment_node = XML::Comment.new(token.data, @doc)
            current.add_child(comment_node)

          when :cdata
            current = @open_stack.last
            cdata_node = XML::CDATA.new(token.data, @doc)
            current.add_child(cdata_node)
          end
        end
      end

      def handle_start_tag(token)
        name = token.name

        # Auto-close logic
        if (closeable = AUTO_CLOSE[name])
          while @open_stack.length > 1 && closeable.include?(@open_stack.last.node_name)
            @open_stack.pop
          end
        end

        node = XML::Node.new(XML::Node::ELEMENT_NODE, name, @doc)
        token.attrs.each { |k, v| node[k] = v }

        @open_stack.last.add_child(node)

        unless VOID_ELEMENTS.include?(name) || token.self_closing
          @open_stack.push(node)
        end
      end

      def handle_end_tag(token)
        name = token.name

        # Find matching open element in stack
        idx = @open_stack.rindex { |n| n.node_name == name }
        return unless idx && idx > 0

        # Pop everything down to and including that element
        @open_stack.slice!(idx..)
      end
    end
  end
end
