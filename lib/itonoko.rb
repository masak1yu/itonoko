# frozen_string_literal: true

require_relative "itonoko/version"
require_relative "itonoko/xml/attr"
require_relative "itonoko/xml/node"
require_relative "itonoko/xml/text"
require_relative "itonoko/xml/node_set"
require_relative "itonoko/xml/document"
require_relative "itonoko/xml/document_fragment"
require_relative "itonoko/html/document"
require_relative "itonoko/html/document_fragment"

# nokogiri互換のトップレベルAPI
module Nokogiri
  module XML
    Node                = Itonoko::XML::Node
    NodeSet             = Itonoko::XML::NodeSet
    Document            = Itonoko::XML::Document
    DocumentFragment    = Itonoko::XML::DocumentFragment
    Text                = Itonoko::XML::Text
    CDATA               = Itonoko::XML::CDATA
    Comment             = Itonoko::XML::Comment
    Attr                = Itonoko::XML::Attr
    ProcessingInstruction = Itonoko::XML::ProcessingInstruction

    def self.parse(string, url = nil, encoding = nil, options = nil, &block)
      doc = Document.parse(string.to_s)
      block&.call(doc)
      doc
    end

    def self.fragment(markup)
      DocumentFragment.parse(markup.to_s)
    end
  end

  module HTML
    Document         = Itonoko::HTML::Document
    DocumentFragment = Itonoko::HTML::DocumentFragment

    def self.parse(string, url = nil, encoding = nil, options = nil, &block)
      doc = Document.parse(string.to_s)
      block&.call(doc)
      doc
    end

    def self.fragment(markup)
      DocumentFragment.parse(markup.to_s)
    end
  end

  HTML4 = HTML
  HTML5 = HTML

  def self.XML(string, *args, &block)
    XML.parse(string, *args, &block)
  end

  def self.HTML(string, *args, &block)
    HTML.parse(string, *args, &block)
  end

  def self.HTML4(string, *args, &block)
    HTML.parse(string, *args, &block)
  end

  def self.HTML5(string, *args, &block)
    HTML.parse(string, *args, &block)
  end
end

# Allow Nokogiri(html) as well as Nokogiri::HTML(html)
def Nokogiri(input = nil, *args, &block)
  Nokogiri::HTML.parse(input.to_s, *args, &block)
end
