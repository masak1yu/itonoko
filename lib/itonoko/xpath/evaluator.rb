# frozen_string_literal: true

require "strscan"
require_relative "../xml/node_set"

module Itonoko
  module XPath
    class Evaluator
      STEP_SPLIT_CACHE = {}
      STEP_PARSE_CACHE = {}

      def initialize(context_node, namespaces = {})
        @context    = context_node
        @namespaces = namespaces
      end

      def evaluate(expr)
        seen   = {}
        result = []
        eval_expr(expr.to_s.strip, [@context], result, seen)
        doc = @context.is_a?(XML::Document) ? @context : @context.document
        XML::NodeSet.new(doc, result)
      end

      private

      # Evaluate a full XPath expression, appending unique nodes into result.
      def eval_expr(expr, context_nodes, result, seen)
        if (parts = split_union(expr)) && parts.length > 1
          parts.each { |p| eval_expr(p.strip, context_nodes, result, seen) }
          return
        end
        eval_location_path(expr, context_nodes, result, seen)
      end

      def split_union(expr)
        parts = []
        depth = 0
        buf   = +""
        expr.each_char do |c|
          case c
          when "(", "[" then depth += 1; buf << c
          when ")", "]" then depth -= 1; buf << c
          when "|"
            if depth == 0
              parts << buf
              buf = +""
            else
              buf << c
            end
          else
            buf << c
          end
        end
        parts << buf
        parts.length > 1 ? parts : nil
      end

      def eval_location_path(expr, context_nodes, result, seen)
        return context_nodes.each { |n| append_unique(n, result, seen) } if expr.empty?

        if expr.start_with?("//")
          expanded = []
          context_nodes.each { |n| expanded << n; all_descendants(n, expanded) }
          eval_steps(expr[2..], expanded, result, seen)
        elsif expr.start_with?("/")
          roots = context_nodes.map { |n| n.is_a?(XML::Document) ? n : n.document }.uniq
          eval_steps(expr[1..], roots, result, seen)
        else
          eval_steps(expr, context_nodes, result, seen)
        end
      end

      def eval_steps(expr, context_nodes, result, seen)
        steps = split_steps(expr)
        if steps.empty?
          context_nodes.each { |n| append_unique(n, result, seen) }
          return
        end

        current = context_nodes
        steps.each_with_index do |step, i|
          any = step.start_with?("/")
          s   = any ? step[1..] : step

          if any
            expanded = []
            current.each { |n| expanded << n; all_descendants(n, expanded) }
            current = expanded
          end

          if i == steps.length - 1
            eval_step(s, current, result, seen)
            return
          else
            buf = []
            eval_step_raw(s, current, buf)
            current = buf
          end
        end
      end

      def split_steps(expr)
        STEP_SPLIT_CACHE[expr] ||= begin
          steps = []
          buf   = +""
          depth = 0
          i     = 0
          while i < expr.length
            c = expr[i]
            if c == "["
              depth += 1; buf << c
            elsif c == "]"
              depth -= 1; buf << c
            elsif c == "/" && depth == 0
              steps << buf.dup unless buf.empty?
              buf.clear
              if expr[i + 1] == "/"
                i += 1
                buf << "/"
              end
            else
              buf << c
            end
            i += 1
          end
          steps << buf.dup unless buf.empty?
          steps.freeze
        end
      end

      def eval_step(step, context_nodes, result, seen)
        return context_nodes.each { |n| append_unique(n, result, seen) } if step.nil? || step.empty?

        axis, node_test, predicates = parse_step(step)

        candidates = []
        context_nodes.each { |ctx| collect_axis_nodes(ctx, axis, candidates) }
        candidates.select! { |n| matches_node_test?(n, node_test) }
        predicates.each { |pred| candidates = apply_predicate(candidates, pred) }
        candidates.each { |n| append_unique(n, result, seen) }
      end

      # Like eval_step but skips per-node dedup — safe for intermediate steps where
      # context_nodes are already unique and :child traversal produces no duplicates.
      def eval_step_raw(step, context_nodes, result)
        return result.concat(context_nodes) if step.nil? || step.empty?

        axis, node_test, predicates = parse_step(step)

        candidates = []
        context_nodes.each { |ctx| collect_axis_nodes(ctx, axis, candidates) }
        candidates.select! { |n| matches_node_test?(n, node_test) }
        predicates.each { |pred| candidates = apply_predicate(candidates, pred) }
        result.concat(candidates)
      end

      def parse_step(step)
        STEP_PARSE_CACHE[step] ||=
          if step == "."
            [:self,   "node()", []]
          elsif step == ".."
            [:parent, "node()", []]
          else
            predicates = []
            main = step
            while (m = main.match(/\[([^\[\]]*)\]\z/))
              predicates.unshift(m[1])
              main = main[0, main.rindex("[")]
            end

            axis      = :child
            node_test = main

            if (idx = main.index("::"))
              axis_str  = main[0, idx]
              node_test = main[(idx + 2)..]
              axis      = axis_from_str(axis_str)
            elsif main.start_with?("@")
              axis      = :attribute
              node_test = main[1..]
            end

            [axis, node_test, predicates]
          end
      end

      def axis_from_str(str)
        case str
        when "child"              then :child
        when "parent"             then :parent
        when "self"               then :self
        when "descendant"         then :descendant
        when "descendant-or-self" then :descendant_or_self
        when "ancestor"           then :ancestor
        when "ancestor-or-self"   then :ancestor_or_self
        when "following-sibling"  then :following_sibling
        when "preceding-sibling"  then :preceding_sibling
        when "attribute"          then :attribute
        else :child
        end
      end

      # Append axis nodes directly into result (no intermediate array allocation).
      def collect_axis_nodes(ctx, axis, result)
        case axis
        when :child
          ch = ctx.children
          result.concat(ch) unless ch.empty?
        when :parent
          result << ctx.parent if ctx.parent
        when :self
          result << ctx
        when :descendant
          all_descendants(ctx, result)
        when :descendant_or_self
          result << ctx
          all_descendants(ctx, result)
        when :ancestor
          collect_ancestors_into(ctx, result)
        when :ancestor_or_self
          result << ctx
          collect_ancestors_into(ctx, result)
        when :following_sibling
          collect_following_siblings_into(ctx, result)
        when :preceding_sibling
          collect_preceding_siblings_into(ctx, result)
        when :attribute
          ctx.attribute_nodes.each { |a| result << a } if ctx.respond_to?(:attribute_nodes)
        end
      end

      def matches_node_test?(node, test)
        case test
        when "node()"    then true
        when "text()"    then node.node_type == XML::Node::TEXT_NODE
        when "comment()" then node.node_type == XML::Node::COMMENT_NODE
        when "processing-instruction()"
          node.node_type == XML::Node::PROCESSING_INSTRUCTION_NODE
        when "*"
          node.node_type == XML::Node::ELEMENT_NODE || node.is_a?(XML::Attr)
        else
          local = test.include?(":") ? test.split(":", 2).last : test
          node.node_name == local
        end
      end

      def apply_predicate(nodes, pred)
        if pred =~ /\A\d+\z/
          idx = pred.to_i - 1
          return (idx >= 0 && idx < nodes.length) ? [nodes[idx]] : []
        end
        if pred == "last()"
          return nodes.last ? [nodes.last] : []
        end
        if (m = pred.match(/\Aposition\(\)\s*=\s*(\d+)\z/))
          idx = m[1].to_i - 1
          return (idx >= 0 && idx < nodes.length) ? [nodes[idx]] : []
        end

        total = nodes.length
        nodes.select.with_index { |node, i| eval_predicate(node, pred, i, total) }
      end

      def eval_predicate(node, pred, pos_index, total)
        case pred
        when /\A@([\w\-:]+)\z/
          node.has_attribute?($1) rescue false
        when /\A@([\w\-:]+)\s*=\s*['"]([^'"]*)['"]\z/
          (node[$1] == $2) rescue false
        when /\A@([\w\-:]+)\s*!=\s*['"]([^'"]*)['"]\z/
          (node[$1] != $2) rescue false
        when /\Acontains\(@([\w\-:]+),\s*['"]([^'"]*)['"]\)\z/
          (node[$1] || "").include?($2) rescue false
        when /\Astarts-with\(@([\w\-:]+),\s*['"]([^'"]*)['"]\)\z/
          (node[$1] || "").start_with?($2) rescue false
        when /\Atext\(\)\s*=\s*['"]([^'"]*)['"]\z/
          node.text == $1
        when /\Anormalize-space\(\)\s*=\s*['"]([^'"]*)['"]\z/
          node.text.strip.gsub(/\s+/, " ") == $1
        when /\Acontains\(text\(\),\s*['"]([^'"]*)['"]\)\z/
          node.text.include?($1)
        when /\Aposition\(\)\s*([<>=!]+)\s*(\d+)\z/
          compare(pos_index + 1, $1, $2.to_i)
        when "last()"
          pos_index == total - 1
        when /\Anot\((.+)\)\z/
          !eval_predicate(node, $1, pos_index, total)
        when /\A[a-zA-Z_][\w\-]*\z/
          node.children.any? { |c| c.node_type == XML::Node::ELEMENT_NODE && c.node_name == pred }
        else
          false
        end
      end

      def compare(a, op, b)
        case op
        when "="  then a == b
        when "!=" then a != b
        when "<"  then a < b
        when "<=" then a <= b
        when ">"  then a > b
        when ">=" then a >= b
        else false
        end
      end

      # Recursive accumulator — O(n) with no intermediate arrays.
      def all_descendants(node, result = [])
        node.children.each do |child|
          result << child
          all_descendants(child, result)
        end
        result
      end

      def collect_ancestors_into(node, result)
        current = node.parent
        while current
          result << current
          current = current.parent
        end
      end

      def collect_following_siblings_into(node, result)
        return unless node.parent
        siblings = node.parent.children
        idx = siblings.index(node)
        return unless idx
        (idx + 1).upto(siblings.length - 1) { |i| result << siblings[i] }
      end

      def collect_preceding_siblings_into(node, result)
        return unless node.parent
        siblings = node.parent.children
        idx = siblings.index(node)
        return unless idx
        (idx - 1).downto(0) { |i| result << siblings[i] }
      end

      def append_unique(node, result, seen)
        id = node.object_id
        unless seen[id]
          seen[id] = true
          result << node
        end
      end
    end
  end
end
