# frozen_string_literal: true

module Itonoko
  module HTML
    class Document < XML::Document
      def self.parse(string, url = nil, encoding = nil, options = nil, &block)
        require_relative "../parser/html_parser"
        Parser::HtmlParser.new.parse(string.to_s)
      end

      def to_html
        children.map(&:to_html).join
      end

      def to_s
        to_html
      end

      def title
        at_css("title")&.text
      end

      def meta_encoding
        node = at_css("meta[charset]")
        return node["charset"] if node
        node = at_css("meta[http-equiv='content-type']")
        return unless node
        node["content"]&.match(/charset=([^\s;]+)/i)&.[](1)
      end
    end
  end
end
