# frozen_string_literal: true

module Itonoko
  module XML
    class Text < Node
      attr_accessor :content

      def initialize(content, document = nil)
        super(TEXT_NODE, "#text", document)
        @content = content.to_s
      end

      def text
        @content
      end
      alias to_s to_html

      def to_html
        escape_text(@content)
      end

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
        super(CDATA_SECTION_NODE, "#cdata-section", document)
        @content = content.to_s
      end

      def text
        @content
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
        super(COMMENT_NODE, "#comment", document)
        @content = content.to_s
      end

      def text
        ""
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
        super(PROCESSING_INSTRUCTION_NODE, target, document)
        @content = content.to_s
      end

      def text
        ""
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
