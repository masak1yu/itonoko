# frozen_string_literal: true

require "strscan"

module Itonoko
  module CSS
    # Produces a flat array of tokens from a CSS selector string.
    class Tokenizer
      Token = Struct.new(:type, :value)

      IDENT_RE       = /[a-zA-Z_\-][a-zA-Z0-9_\-]*/
      IDENT_STAR_RE  = /[a-zA-Z_\-*][a-zA-Z0-9_\-]*/

      def tokenize(str)
        scanner = StringScanner.new(str.to_s.strip)
        tokens  = []

        until scanner.eos?
          if scanner.scan(/\s*,\s*/)
            tokens << Token.new(:comma, ",")

          elsif scanner.scan(/\s*>\s*/)
            tokens << Token.new(:combinator, ">")

          elsif scanner.scan(/\s*\+\s*/)
            tokens << Token.new(:combinator, "+")

          elsif scanner.scan(/\s*~\s*/)
            tokens << Token.new(:combinator, "~")

          elsif scanner.scan(/\s+/)
            # Descendant combinator (whitespace) — only emit if meaningful
            tokens << Token.new(:combinator, " ") unless tokens.empty? || tokens.last.type == :comma

          elsif scanner.scan(/\*/)
            tokens << Token.new(:universal, "*")

          elsif scanner.scan(/#(#{IDENT_RE})/o)
            tokens << Token.new(:id, scanner[1])

          elsif scanner.scan(/\.(#{IDENT_RE})/o)
            tokens << Token.new(:class, scanner[1])

          elsif scanner.scan(/:not\(/i)
            inner = scan_balanced_paren(scanner)
            tokens << Token.new(:pseudo, "not(#{inner})")

          elsif scanner.scan(/::?(#{IDENT_RE}(?:\([^)]*\))?)/o)
            tokens << Token.new(:pseudo, scanner[1])

          elsif scanner.scan(/\[/)
            attr_token = scan_attribute(scanner)
            tokens << attr_token

          elsif scanner.scan(/(#{IDENT_STAR_RE})/o)
            tokens << Token.new(:tag, scanner[1])

          else
            scanner.getch  # skip unknown char
          end
        end

        tokens
      end

      private

      def scan_balanced_paren(scanner)
        inner = +""
        depth = 1
        until scanner.eos? || depth == 0
          c = scanner.getch
          depth += 1 if c == "("
          if c == ")"
            depth -= 1
            break if depth == 0
          end
          inner << c
        end
        inner
      end

      def scan_attribute(scanner)
        name = scanner.scan(/[^\s=\]~|^$*]+/) || ""
        scanner.scan(/\s*/)

        op  = scanner.scan(/[~|^$*]?=/)
        scanner.scan(/\s*/)

        if op
          if scanner.scan(/"/)
            val = scanner.scan(/[^"]*/)
            scanner.scan(/"/)
          elsif scanner.scan(/'/)
            val = scanner.scan(/[^']*/)
            scanner.scan(/'/)
          else
            val = scanner.scan(/[^\]]+/)
          end
          scanner.scan(/\s*\]/)
          Token.new(:attr, { name: name.strip, op: op, value: (val || "").strip })
        else
          scanner.scan(/\s*\]/)
          Token.new(:attr, { name: name.strip, op: nil, value: nil })
        end
      end
    end
  end
end
