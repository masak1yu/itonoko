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
        groups.any? { |group| matches_group_at?(node, group, group.length - 1) }
      end

      def initialize(context_node)
        @context = context_node
      end

      def match(selector_str)
        groups = Parser.new.parse(selector_str)
        doc    = document_of(@context)
        seen   = {}
        result = []

        all_elements(@context, result)
        result.select! do |node|
          unless seen[node.object_id]
            seen[node.object_id] = true
            groups.any? { |group| self.class.matches_group_at?(node, group, group.length - 1) }
          end
        end

        XML::NodeSet.new(doc, result)
      end

      # Index-based group match — no Array slicing, no array allocation for ancestor walk.
      def self.matches_group_at?(node, steps, idx)
        return false unless node.node_type == XML::Node::ELEMENT_NODE
        return false unless matches_simple?(node, steps[idx].simple)
        return true  if idx == 0

        combinator = steps[idx].combinator || " "
        prev_idx   = idx - 1

        case combinator
        when ">"
          par = node.parent
          par && par.node_type == XML::Node::ELEMENT_NODE &&
            matches_group_at?(par, steps, prev_idx)

        when "+"
          sib = node.previous_sibling
          sib = sib.previous_sibling while sib && sib.node_type != XML::Node::ELEMENT_NODE
          sib && matches_group_at?(sib, steps, prev_idx)

        when "~"
          sib = node.previous_sibling
          while sib
            return true if sib.node_type == XML::Node::ELEMENT_NODE &&
                           matches_group_at?(sib, steps, prev_idx)
            sib = sib.previous_sibling
          end
          false

        else  # " " descendant
          cur = node.parent
          while cur
            return false if cur.node_type == XML::Node::DOCUMENT_NODE
            return true  if cur.node_type == XML::Node::ELEMENT_NODE &&
                            matches_group_at?(cur, steps, prev_idx)
            cur = cur.parent
          end
          false
        end
      end

      def self.matches_simple?(node, simple)
        return false unless node.node_type == XML::Node::ELEMENT_NODE
        return false unless matches_tag?(node, simple.tag)
        return false unless simple.ids.all? { |id| node["id"] == id }
        return false unless simple.classes.all? { |cls| node_has_class?(node, cls) }
        return false unless simple.attrs.all? { |attr| matches_attr?(node, attr) }
        return false unless simple.pseudos.all? { |pseudo| matches_pseudo?(node, pseudo) }
        true
      end

      # Compare tag without allocating downcased strings when not needed.
      def self.matches_tag?(node, tag)
        return true if tag.nil? || tag == "*"
        nn = node.node_name
        nn == tag || nn.downcase == tag
      end

      # Avoid String#split — use String#index for O(1) space word-boundary check.
      def self.node_has_class?(node, cls)
        val = node["class"] or return false
        len = cls.length
        i   = 0
        while (idx = val.index(cls, i))
          before_ok = idx == 0          || val.getbyte(idx - 1) == 32
          after_ok  = idx + len == val.length || val.getbyte(idx + len) == 32
          return true if before_ok && after_ok
          i = idx + 1
        end
        false
      end

      def self.matches_attr?(node, attr_spec)
        name   = attr_spec[:name]
        op     = attr_spec[:op]
        value  = attr_spec[:value]
        actual = node[name]
        return !actual.nil? if op.nil?
        return false        if actual.nil?
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

      def self.matches_pseudo?(node, pseudo)
        name = pseudo[:name]
        arg  = pseudo[:arg]

        case name
        when "first-child"
          first_element_child_of(node.parent) == node
        when "last-child"
          last_element_child_of(node.parent) == node
        when "first-of-type"
          first_of_type_in(node) == node
        when "last-of-type"
          last_of_type_in(node) == node
        when "only-child"
          element_child_count(node.parent) == 1
        when "only-of-type"
          type_child_count(node.parent, node.node_name) == 1
        when "nth-child"
          i = element_index_of(node)
          i && nth_match?(i, parse_nth(arg))
        when "nth-last-child"
          i = element_index_of(node)
          i && nth_match?(element_child_count(node.parent) - i + 1, parse_nth(arg))
        when "nth-of-type"
          i = type_index_of(node)
          i && nth_match?(i, parse_nth(arg))
        when "nth-last-of-type"
          i = type_index_of(node)
          i && nth_match?(type_child_count(node.parent, node.node_name) - i + 1, parse_nth(arg))
        when "empty"
          node.children.none? do |c|
            c.node_type == XML::Node::ELEMENT_NODE ||
              (c.is_a?(XML::Text) && !c.content.empty?)
          end
        when "root"
          node.parent&.node_type == XML::Node::DOCUMENT_NODE
        when "not"
          return true unless arg && !arg.empty?
          !matches_selector?(node, arg)
        when "checked"  then node["checked"] || node["selected"]
        when "disabled" then node["disabled"]
        when "enabled"  then !node["disabled"]
        else false
        end
      end

      # ── sibling helpers (no Array allocation) ─────────────────

      def self.first_element_child_of(parent)
        return nil unless parent
        parent.children.each { |c| return c if c.node_type == XML::Node::ELEMENT_NODE }
        nil
      end

      def self.last_element_child_of(parent)
        return nil unless parent
        last = nil
        parent.children.each { |c| last = c if c.node_type == XML::Node::ELEMENT_NODE }
        last
      end

      def self.element_child_count(parent)
        return 0 unless parent
        parent.children.count { |c| c.node_type == XML::Node::ELEMENT_NODE }
      end

      def self.element_index_of(node)
        return nil unless node.parent
        idx = 0
        node.parent.children.each do |c|
          next unless c.node_type == XML::Node::ELEMENT_NODE
          idx += 1
          return idx if c.equal?(node)
        end
        nil
      end

      def self.first_of_type_in(node)
        return nil unless node.parent
        name = node.node_name
        node.parent.children.each do |c|
          return c if c.node_type == XML::Node::ELEMENT_NODE && c.node_name == name
        end
        nil
      end

      def self.last_of_type_in(node)
        return nil unless node.parent
        name = node.node_name
        last = nil
        node.parent.children.each { |c| last = c if c.node_type == XML::Node::ELEMENT_NODE && c.node_name == name }
        last
      end

      def self.type_index_of(node)
        return nil unless node.parent
        name = node.node_name
        idx  = 0
        node.parent.children.each do |c|
          next unless c.node_type == XML::Node::ELEMENT_NODE && c.node_name == name
          idx += 1
          return idx if c.equal?(node)
        end
        nil
      end

      def self.type_child_count(parent, name)
        return 0 unless parent
        parent.children.count { |c| c.node_type == XML::Node::ELEMENT_NODE && c.node_name == name }
      end

      def self.parse_nth(arg)
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

      def self.nth_match?(index, nth)
        a, b = nth[:a], nth[:b]
        if a == 0
          index == b
        else
          n = (index - b).to_f / a
          n >= 0 && n == n.floor
        end
      end

      private

      def all_elements(root, result)
        root.children.each do |child|
          if child.node_type == XML::Node::ELEMENT_NODE
            result << child
            all_elements(child, result)
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
