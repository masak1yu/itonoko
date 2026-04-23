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

      AUTO_CLOSE = {
        "p"        => %w[p],
        "li"       => %w[li],
        "dt"       => %w[dt dd],
        "dd"       => %w[dd dt],
        "td"       => %w[td th],
        "th"       => %w[td th],
        "tr"       => %w[tr],
        "colgroup" => %w[colgroup],
        "caption"  => %w[caption],
        "option"   => %w[option],
        "optgroup" => %w[optgroup option],
        "rb"       => %w[rb rt rtc rp],
        "rt"       => %w[rb rt rp],
        "rp"       => %w[rb rt rtc rp],
        "rtc"      => %w[rb rtc rp],
      }.freeze

      def parse(html)
        @doc        = HTML::Document.new
        @doc.errors = []
        @open_stack = [@doc]
        @buf        = +""          # reused mutable buffer, never reallocated
        tokenize_and_build(StringScanner.new(html.to_s))
        @doc
      end

      private

      # Single-pass: tokenize and build the DOM tree simultaneously.
      # No Token objects, no intermediate token array.
      def tokenize_and_build(sc)
        until sc.eos?
          if sc.scan(/<!--/)
            flush_buf
            comment = scan_until(sc, /-->|--!>/)
            @open_stack.last.append_child(XML::Comment.new(comment, @doc))

          elsif sc.scan(/<!\[CDATA\[/)
            flush_buf
            cdata = scan_until(sc, /\]\]>/)
            @open_stack.last.append_child(XML::CDATA.new(cdata, @doc))

          elsif sc.scan(/<!DOCTYPE/i)
            sc.scan(/[^>]*/)
            sc.scan(/>/)

          elsif sc.scan(/<\//)
            flush_buf
            name = (sc.scan(/[^\s>\/]+/) || "").downcase
            sc.scan(/[^>]*/)
            sc.scan(/>/)
            handle_end_tag(name)

          elsif sc.scan(/</) && sc.check(/[a-zA-Z_!]/)
            flush_buf
            name  = (sc.scan(/[^\s>\/]+/) || "").downcase
            attrs = {}

            if RAW_TEXT_ELEMENTS.include?(name)
              scan_attributes(sc, attrs)
              self_closing = sc.scan(/\//) ? true : false
              sc.scan(/>/)
              handle_start_tag(name, attrs, self_closing)
              unless self_closing
                raw = scan_until(sc, /<\/#{Regexp.escape(name)}\s*>/i)
                @open_stack.last.append_child(XML::Text.new(raw, @doc)) unless raw.empty?
                handle_end_tag(name)
              end
            else
              scan_attributes(sc, attrs)
              self_closing = sc.scan(/\//) ? true : false
              sc.scan(/>/)
              handle_start_tag(name, attrs, self_closing)
            end

          elsif (chunk = sc.scan(/[^<]+/))
            @buf << chunk
          else
            @buf << sc.getch
          end
        end
        flush_buf
      end

      # Scan until pattern; consume the pattern and return content before it.
      # StringScanner#scan_until is a C method that advances in bulk.
      def scan_until(sc, pattern)
        hit = sc.scan_until(pattern)
        return sc.rest.tap { sc.terminate } unless hit
        hit[0, hit.length - sc.matched_size]
      end

      # Scan attributes into attrs hash.
      def scan_attributes(sc, attrs)
        loop do
          sc.scan(/\s+/)
          break if sc.eos? || sc.check(/[>\/]/)
          attr_name = sc.scan(/[^\s=>\/"']+/) or break
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
            k = attr_name.match?(/[A-Z]/) ? attr_name.downcase : attr_name
            attrs[k] = decode_entities(val)
          else
            k = attr_name.match?(/[A-Z]/) ? attr_name.downcase : attr_name
            attrs[k] = k
          end
        end
      end

      def flush_buf
        return if @buf.empty?
        text = decode_entities(@buf)
        @open_stack.last.append_child(XML::Text.new(text, @doc)) unless (@open_stack.length == 1 && text.strip.empty?)
        @buf.clear
      end

      def decode_entities(str)
        # Always return a new string so @buf.clear doesn't clobber the copy
        # stored in XML::Text#content.
        return str.dup unless str.include?("&")
        str.gsub(/&([^;\s]{1,10});/) { Parser.decode_entity($1) }
      end

      def handle_start_tag(name, attrs, self_closing)
        if (closeable = AUTO_CLOSE[name])
          while @open_stack.length > 1 && closeable.include?(@open_stack.last.node_name)
            @open_stack.pop
          end
        end

        node = XML::Node.new(XML::Node::ELEMENT_NODE, name, @doc)
        attrs.each { |k, v| node[k] = v }
        @open_stack.last.append_child(node)
        @open_stack.push(node) unless VOID_ELEMENTS.include?(name) || self_closing
      end

      def handle_end_tag(name)
        idx = @open_stack.rindex { |n| n.node_name == name }
        @open_stack.slice!(idx..) if idx && idx > 0
      end
    end
  end
end
