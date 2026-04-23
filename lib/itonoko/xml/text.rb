# frozen_string_literal: true

module Itonoko
  module XML
    class Text < Node
      attr_accessor :content

      def initialize(content, document = nil)
        # Bypass Node#initialize to avoid allocating unused @children / @attributes arrays.
        @node_type  = TEXT_NODE
        @node_name  = "#text"
        @document   = document
        @parent     = nil
        @children   = EMPTY_CHILDREN
        @attributes = EMPTY_ATTRS
        @content    = content.to_s
      end

      def text
        @content
      end

      def _collect_text(buf)
        buf << @content
      end

      def to_html
        escape_text(@content)
      end
      alias to_s to_html

      def to_xml(_options = {})
        escape_text(@content)
      end

      def node_name
        "#text"
      end
    end

    class CDATA < Node
      attr_accessor :content

      def initialize(content, document = nil)
        @node_type  = CDATA_SECTION_NODE
        @node_name  = "#cdata-section"
        @document   = document
        @parent     = nil
        @children   = EMPTY_CHILDREN
        @attributes = EMPTY_ATTRS
        @content    = content.to_s
      end

      def text
        @content
      end

      def _collect_text(buf)
        buf << @content
      end

      def to_html
        @content
      end

      def to_xml(_options = {})
        "<![CDATA[#{@content}]]>"
      end

      def node_name
        "#cdata-section"
      end
    end

    class Comment < Node
      attr_accessor :content

      def initialize(content, document = nil)
        @node_type  = COMMENT_NODE
        @node_name  = "#comment"
        @document   = document
        @parent     = nil
        @children   = EMPTY_CHILDREN
        @attributes = EMPTY_ATTRS
        @content    = content.to_s
      end

      def text
        ""
      end

      def _collect_text(_buf)
        # Comments don't contribute to text content.
      end

      def to_html
        "<!--#{@content}-->"
      end

      def to_xml(_options = {})
        "<!--#{@content}-->"
      end

      def node_name
        "#comment"
      end
    end

    class ProcessingInstruction < Node
      attr_accessor :content

      def initialize(target, content, document = nil)
        @node_type  = PROCESSING_INSTRUCTION_NODE
        @node_name  = target
        @document   = document
        @parent     = nil
        @children   = EMPTY_CHILDREN
        @attributes = EMPTY_ATTRS
        @content    = content.to_s
      end

      def text
        ""
      end

      def _collect_text(_buf)
      end

      def to_html
        "<?#{node_name} #{@content}?>"
      end

      def to_xml(_options = {})
        "<?#{node_name} #{@content}?>"
      end
    end
  end
end
