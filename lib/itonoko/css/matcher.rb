# frozen_string_literal: true

require_relative "parser"
require_relative "../xml/node_set"

module Itonoko
  module CSS
    class Matcher
      def self.match(context_node, selector_str)
        new(context_node).match(selector_str)
      end

      def self.matches_selector?(node, selector_str)
        groups = Parser.new.parse(selector_str)
        groups.any? { |group| new(nil).matches_group?(node, group) }
      end

      def initialize(context_node)
        @context = context_node
      end

      def match(selector_str)
        groups = Parser.new.parse(selector_str)
        doc    = document_of(@context)
        seen   = {}
        result = []

        all_elements(@context).each do |node|
          next if seen[node.object_id]
          if groups.any? { |group| matches_group?(node, group) }
            seen[node.object_id] = true
            result << node
          end
        end

        XML::NodeSet.new(doc, result)
      end

      # Returns true if node matches the given selector group (list of Steps).
      def matches_group?(node, steps)
        return false if steps.empty?

        # The rightmost step must match the node itself.
        last_step = steps.last
        return false unless matches_simple?(node, last_step.simple)

        # Walk leftward through the remaining steps.
        remaining = steps[0..-2]
        return true if remaining.empty?

        prev_step = remaining.last
        combinator = last_step.combinator || " "

        candidate_ancestors = candidates_for_combinator(node, combinator)
        candidate_ancestors.any? do |candidate|
          matches_group?(candidate, remaining)
        end
      end

      private

      def candidates_for_combinator(node, combinator)
        case combinator
        when ">"
          node.parent ? [node.parent] : []
        when "+"
          prev = node.previous_sibling
          prev = prev.previous_sibling while prev && prev.node_type != XML::Node::ELEMENT_NODE
          prev ? [prev] : []
        when "~"
          collect_preceding_siblings(node)
        else  # " " (descendant)
          collect_ancestors(node)
        end
      end

      def collect_ancestors(node)
        result = []
        current = node.parent
        while current && current.node_type != XML::Node::DOCUMENT_NODE
          result << current if current.node_type == XML::Node::ELEMENT_NODE
          current = current.parent
        end
        result
      end

      def collect_preceding_siblings(node)
        result = []
        current = node.previous_sibling
        while current
          result << current if current.node_type == XML::Node::ELEMENT_NODE
          current = current.previous_sibling
        end
        result
      end

      def matches_simple?(node, simple)
        return false unless node.node_type == XML::Node::ELEMENT_NODE
        return false unless matches_tag?(node, simple.tag)
        return false unless simple.ids.all? { |id| node["id"] == id }
        return false unless simple.classes.all? { |cls| node_has_class?(node, cls) }
        return false unless simple.attrs.all? { |attr| matches_attr?(node, attr) }
        return false unless simple.pseudos.all? { |pseudo| matches_pseudo?(node, pseudo) }
        true
      end

      def matches_tag?(node, tag)
        return true if tag.nil? || tag == "*"
        node.node_name.downcase == tag.downcase
      end

      def node_has_class?(node, cls)
        classes = (node["class"] || "").split
        classes.include?(cls)
      end

      def matches_attr?(node, attr_spec)
        name  = attr_spec[:name]
        op    = attr_spec[:op]
        value = attr_spec[:value]

        actual = node[name]
        return !actual.nil? if op.nil?
        return false if actual.nil?

        case op
        when "="  then actual == value
        when "~=" then actual.split.include?(value)
        when "|=" then actual == value || actual.start_with?("#{value}-")
        when "^=" then actual.start_with?(value)
        when "$=" then actual.end_with?(value)
        when "*=" then actual.include?(value)
        else actual == value
        end
      end

      def matches_pseudo?(node, pseudo)
        name = pseudo[:name]
        arg  = pseudo[:arg]

        case name
        when "first-child"
          element_siblings(node).first == node
        when "last-child"
          element_siblings(node).last == node
        when "first-of-type"
          same_type_siblings(node).first == node
        when "last-of-type"
          same_type_siblings(node).last == node
        when "only-child"
          element_siblings(node).length == 1
        when "only-of-type"
          same_type_siblings(node).length == 1
        when "nth-child"
          idx = element_siblings(node).index(node)
          return false unless idx
          nth_match?(idx + 1, parse_nth(arg))
        when "nth-last-child"
          siblings = element_siblings(node)
          idx = siblings.index(node)
          return false unless idx
          nth_match?(siblings.length - idx, parse_nth(arg))
        when "nth-of-type"
          siblings = same_type_siblings(node)
          idx = siblings.index(node)
          return false unless idx
          nth_match?(idx + 1, parse_nth(arg))
        when "nth-last-of-type"
          siblings = same_type_siblings(node)
          idx = siblings.index(node)
          return false unless idx
          nth_match?(siblings.length - idx, parse_nth(arg))
        when "empty"
          node.children.none? { |c| c.node_type == XML::Node::ELEMENT_NODE || (c.is_a?(XML::Text) && !c.content.empty?) }
        when "root"
          node.parent&.node_type == XML::Node::DOCUMENT_NODE
        when "not"
          return true unless arg && !arg.empty?
          !Matcher.matches_selector?(node, arg)
        when "checked"
          node["checked"] || node["selected"]
        when "disabled"
          node["disabled"]
        when "enabled"
          !node["disabled"]
        when "link", "visited", "hover", "focus", "active"
          false  # dynamic pseudos not applicable
        when "first-line", "first-letter", "before", "after"
          false  # pseudo-elements
        else
          false
        end
      end

      def element_siblings(node)
        return [] unless node.parent
        node.parent.children.select { |c| c.node_type == XML::Node::ELEMENT_NODE }
      end

      def same_type_siblings(node)
        return [] unless node.parent
        node.parent.children.select { |c| c.node_type == XML::Node::ELEMENT_NODE && c.node_name == node.node_name }
      end

      def parse_nth(arg)
        return { a: 0, b: 1 } unless arg
        arg = arg.strip.downcase

        case arg
        when "odd"  then { a: 2, b: 1 }
        when "even" then { a: 2, b: 0 }
        when /\A([+-]?\d+)\z/
          { a: 0, b: $1.to_i }
        when /\A([+-]?\d*)n(?:\s*([+-]\s*\d+))?\z/
          a_str = $1
          b_str = $2&.gsub(/\s/, "")
          a = a_str.empty? || a_str == "+" ? 1 : a_str == "-" ? -1 : a_str.to_i
          b = b_str ? b_str.to_i : 0
          { a: a, b: b }
        else
          { a: 0, b: 0 }
        end
      end

      def nth_match?(index, nth)
        a = nth[:a]
        b = nth[:b]
        if a == 0
          index == b
        else
          n = (index - b).to_f / a
          n >= 0 && n == n.floor
        end
      end

      def all_elements(root)
        result = []
        traverse(root, result)
        result
      end

      def traverse(node, result)
        node.children.each do |child|
          if child.node_type == XML::Node::ELEMENT_NODE
            result << child
            traverse(child, result)
          end
        end
      end

      def document_of(node)
        return node if node.is_a?(XML::Document)
        node&.document
      end
    end
  end
end
