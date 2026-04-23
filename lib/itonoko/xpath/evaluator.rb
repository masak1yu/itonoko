# frozen_string_literal: true

require "strscan"
require_relative "../xml/node_set"

module Itonoko
  module XPath
    class Evaluator
      def initialize(context_node, namespaces = {})
        @context   = context_node
        @namespaces = namespaces
      end

      def evaluate(expr)
        nodes = eval_expr(expr.to_s.strip, [@context])
        doc   = @context.is_a?(XML::Document) ? @context : @context.document
        XML::NodeSet.new(doc, nodes.flatten.uniq { |n| n.object_id })
      end

      private

      # Entry: evaluate a full XPath expression from given context nodes.
      def eval_expr(expr, context_nodes)
        # Handle union
        if (parts = split_union(expr)) && parts.length > 1
          return parts.flat_map { |p| eval_expr(p.strip, context_nodes) }.uniq { |n| n.object_id }
        end

        eval_location_path(expr, context_nodes)
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

      # Evaluate a location path like //div/span[@class] or ./text()
      def eval_location_path(expr, context_nodes)
        return context_nodes if expr.empty?

        # Absolute path: starts with //
        if expr.start_with?("//")
          rest = expr[2..]
          return eval_steps(rest, context_nodes, absolute: true, any_depth: true)
        end

        # Absolute path: starts with /
        if expr.start_with?("/")
          roots = context_nodes.map { |n| n.is_a?(XML::Document) ? n : n.document }.uniq
          rest  = expr[1..]
          return eval_steps(rest, roots, absolute: false, any_depth: false)
        end

        eval_steps(expr, context_nodes, absolute: false, any_depth: false)
      end

      def eval_steps(expr, context_nodes, absolute: false, any_depth: false)
        if any_depth
          context_nodes = context_nodes.flat_map { |n| [n] + all_descendants(n) }
        end

        steps = split_steps(expr)
        return context_nodes if steps.empty?

        first_step = steps.first
        rest_steps = steps[1..]

        result = eval_step(first_step, context_nodes)

        rest_steps.each do |step|
          any = step.start_with?("/")
          s   = any ? step[1..] : step
          if any
            result = result.flat_map { |n| [n] + all_descendants(n) }
          end
          result = eval_step(s, result)
        end

        result
      end

      # Split "//foo/bar//baz" respecting brackets
      def split_steps(expr)
        steps = []
        buf   = +""
        depth = 0
        i     = 0

        while i < expr.length
          c = expr[i]
          if c == "["
            depth += 1
            buf << c
          elsif c == "]"
            depth -= 1
            buf << c
          elsif c == "/" && depth == 0
            steps << buf unless buf.empty?
            buf = +""
            if expr[i + 1] == "/"
              i += 1
              steps << buf unless buf.empty?
              buf = +"/"  # prefix next step with / to signal any-depth
            end
          else
            buf << c
          end
          i += 1
        end
        steps << buf unless buf.empty?
        steps
      end

      def eval_step(step, context_nodes)
        return context_nodes if step.nil? || step.empty?

        # Parse axis::nodetest[predicates]
        axis, node_test, predicates = parse_step(step)

        result = context_nodes.flat_map { |ctx| axis_nodes(ctx, axis) }
        result = result.select { |n| matches_node_test?(n, node_test) }
        predicates.each { |pred| result = apply_predicate(result, pred) }
        result
      end

      def parse_step(step)
        # Handle abbreviated steps
        return [:self,   "node()", []] if step == "."
        return [:parent, "node()", []] if step == ".."

        # Separate predicates
        predicates = []
        main = step
        while (m = main.match(/\[([^\[\]]*)\]\z/))
          predicates.unshift(m[1])
          main = main[0, main.rindex("[")]
        end

        # Axis
        axis = :child
        node_test = main

        if (idx = main.index("::"))
          axis_str  = main[0, idx]
          node_test = main[(idx + 2)..]
          axis = axis_from_str(axis_str)
        elsif main.start_with?("@")
          axis      = :attribute
          node_test = main[1..]
        end

        [axis, node_test, predicates]
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
        when "following"          then :following
        when "preceding"          then :preceding
        else :child
        end
      end

      def axis_nodes(ctx, axis)
        case axis
        when :child              then ctx.children
        when :parent             then ctx.parent ? [ctx.parent] : []
        when :self               then [ctx]
        when :descendant         then all_descendants(ctx)
        when :descendant_or_self then [ctx] + all_descendants(ctx)
        when :ancestor           then ancestors(ctx)
        when :ancestor_or_self   then [ctx] + ancestors(ctx)
        when :following_sibling  then following_siblings(ctx)
        when :preceding_sibling  then preceding_siblings(ctx)
        when :attribute          then ctx.respond_to?(:attribute_nodes) ? ctx.attribute_nodes : []
        when :following          then []  # complex; skipped
        when :preceding          then []
        else ctx.children
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
          node.node_name == local || (node.respond_to?(:name) && node.name == local)
        end
      end

      def apply_predicate(nodes, pred)
        # Numeric predicate
        if pred =~ /\A\d+\z/
          idx = pred.to_i - 1
          return idx >= 0 && idx < nodes.length ? [nodes[idx]] : []
        end

        # last()
        if pred == "last()"
          return nodes.last ? [nodes.last] : []
        end

        # position() = n
        if (m = pred.match(/\Aposition\(\)\s*=\s*(\d+)\z/))
          idx = m[1].to_i - 1
          return idx >= 0 && idx < nodes.length ? [nodes[idx]] : []
        end

        # Filter each node
        nodes.select.with_index { |node, i| eval_predicate(node, pred, i, nodes.length) }
      end

      def eval_predicate(node, pred, pos_index, total)
        # Attribute existence: @attr
        if pred =~ /\A@([\w\-:]+)\z/
          return node.has_attribute?($1) rescue false

        # @attr = 'value' or @attr = "value"
        elsif pred =~ /\A@([\w\-:]+)\s*=\s*['"]([^'"]*)['"]\z/
          return (node[$1] == $2) rescue false

        # @attr != 'value'
        elsif pred =~ /\A@([\w\-:]+)\s*!=\s*['"]([^'"]*)['"]\z/
          return (node[$1] != $2) rescue false

        # @attr contains/starts-with etc via contains()
        elsif pred =~ /\Acontains\(@([\w\-:]+),\s*['"]([^'"]*)['"]\)\z/
          val = node[$1] rescue nil
          return val&.include?($2) || false

        elsif pred =~ /\Astarts-with\(@([\w\-:]+),\s*['"]([^'"]*)['"]\)\z/
          val = node[$1] rescue nil
          return val&.start_with?($2) || false

        # text() = 'value'
        elsif pred =~ /\Atext\(\)\s*=\s*['"]([^'"]*)['"]\z/
          return node.text == $1

        # normalize-space() = 'value'
        elsif pred =~ /\Anormalize-space\(\)\s*=\s*['"]([^'"]*)['"]\z/
          return node.text.strip.gsub(/\s+/, " ") == $1

        # contains(text(), 'value')
        elsif pred =~ /\Acontains\(text\(\),\s*['"]([^'"]*)['"]\)\z/
          return node.text.include?($1)

        # position()
        elsif pred =~ /\Aposition\(\)\s*([<>=!]+)\s*(\d+)\z/
          op  = $1
          val = $2.to_i
          pos = pos_index + 1
          compare(pos, op, val)

        # last()
        elsif pred == "last()"
          pos_index == total - 1

        # not(...)
        elsif pred =~ /\Anot\((.+)\)\z/
          !eval_predicate(node, $1, pos_index, total)

        # child element existence: tagname
        elsif pred =~ /\A[a-zA-Z_][\w\-]*\z/
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

      def all_descendants(node)
        result = []
        node.children.each do |child|
          result << child
          result.concat(all_descendants(child))
        end
        result
      end

      def ancestors(node)
        result = []
        current = node.parent
        while current
          result << current
          current = current.parent
        end
        result
      end

      def following_siblings(node)
        return [] unless node.parent
        siblings = node.parent.children
        idx      = siblings.index(node)
        return [] unless idx
        siblings[(idx + 1)..]
      end

      def preceding_siblings(node)
        return [] unless node.parent
        siblings = node.parent.children
        idx      = siblings.index(node)
        return [] unless idx
        siblings[0, idx].reverse
      end
    end
  end
end
