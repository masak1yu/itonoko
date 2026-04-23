# frozen_string_literal: true

require_relative "tokenizer"

module Itonoko
  module CSS
    # Parses a tokenized CSS selector into a list of selector groups.
    #
    # Result structure:
    #   [SelectorGroup, ...]
    #
    # SelectorGroup = array of Step objects connected by combinators:
    #   [{ combinator: " "|">"|"+"|"~"|nil, simple: SimpleSelector }, ...]
    #
    # SimpleSelector = { tag:, ids:, classes:, attrs:, pseudos: }
    class Parser
      Step           = Struct.new(:combinator, :simple)
      SimpleSelector = Struct.new(:tag, :ids, :classes, :attrs, :pseudos, keyword_init: true)

      def parse(selector_str)
        tokens = Tokenizer.new.tokenize(selector_str)
        parse_selector_list(tokens)
      end

      private

      def parse_selector_list(tokens)
        groups   = []
        current  = []
        i        = 0

        while i < tokens.length
          tok = tokens[i]

          if tok.type == :comma
            groups << current unless current.empty?
            current = []
            i += 1
            next
          end

          if tok.type == :combinator
            combinator = tok.value
            i += 1
            simple, i = parse_simple_selector(tokens, i)
            current << Step.new(combinator, simple) if simple
          else
            simple, i = parse_simple_selector(tokens, i)
            current << Step.new(nil, simple) if simple
          end
        end

        groups << current unless current.empty?
        groups
      end

      def parse_simple_selector(tokens, i)
        simple = SimpleSelector.new(tag: nil, ids: [], classes: [], attrs: [], pseudos: [])
        found  = false

        while i < tokens.length
          tok = tokens[i]

          case tok.type
          when :tag
            simple.tag = tok.value
            found = true
            i += 1
          when :universal
            simple.tag = "*"
            found = true
            i += 1
          when :id
            simple.ids << tok.value
            found = true
            i += 1
          when :class
            simple.classes << tok.value
            found = true
            i += 1
          when :attr
            simple.attrs << tok.value
            found = true
            i += 1
          when :pseudo
            simple.pseudos << parse_pseudo(tok.value)
            found = true
            i += 1
          when :combinator, :comma
            break
          else
            break
          end
        end

        return nil, i unless found
        [simple, i]
      end

      def parse_pseudo(str)
        if str =~ /\A([a-zA-Z\-]+)\(([^)]*)\)\z/
          { name: $1.downcase, arg: $2.strip }
        else
          { name: str.downcase, arg: nil }
        end
      end
    end
  end
end
