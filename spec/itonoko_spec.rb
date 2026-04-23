# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/itonoko"

class HtmlParserTest < Minitest::Test
  def setup
    html = <<~HTML
      <!DOCTYPE html>
      <html>
        <head><title>Test Page</title></head>
        <body>
          <div id="main" class="container">
            <h1>Hello World</h1>
            <p class="intro">First paragraph</p>
            <p class="outro">Second paragraph</p>
            <ul>
              <li>Item 1</li>
              <li>Item 2</li>
              <li>Item 3</li>
            </ul>
            <a href="https://example.com" data-track="nav">Link</a>
          </div>
        </body>
      </html>
    HTML
    @doc = Nokogiri::HTML(html)
  end

  def test_parse_returns_document
    assert_kind_of Nokogiri::HTML::Document, @doc
  end

  def test_title
    assert_equal "Test Page", @doc.title
  end

  def test_css_by_tag
    h1 = @doc.css("h1")
    assert_equal 1, h1.length
    assert_equal "Hello World", h1.first.text
  end

  def test_css_by_id
    main = @doc.css("#main")
    assert_equal 1, main.length
    assert_equal "main", main.first["id"]
  end

  def test_css_by_class
    intros = @doc.css(".intro")
    assert_equal 1, intros.length
    assert_equal "First paragraph", intros.first.text
  end

  def test_css_multiple_classes
    paras = @doc.css("p.intro")
    assert_equal 1, paras.length
  end

  def test_css_descendant
    lis = @doc.css("ul li")
    assert_equal 3, lis.length
  end

  def test_css_child_combinator
    divs = @doc.css("body > div")
    assert_equal 1, divs.length
  end

  def test_css_attribute_selector
    links = @doc.css("a[href]")
    assert_equal 1, links.length
  end

  def test_css_attribute_value
    links = @doc.css("a[data-track='nav']")
    assert_equal 1, links.length
  end

  def test_css_attribute_prefix
    links = @doc.css("a[href^='https']")
    assert_equal 1, links.length
  end

  def test_css_first_child
    first_li = @doc.css("li:first-child")
    assert_equal 1, first_li.length
    assert_equal "Item 1", first_li.first.text
  end

  def test_css_last_child
    last_li = @doc.css("li:last-child")
    assert_equal 1, last_li.length
    assert_equal "Item 3", last_li.first.text
  end

  def test_css_nth_child
    second_li = @doc.css("li:nth-child(2)")
    assert_equal 1, second_li.length
    assert_equal "Item 2", second_li.first.text
  end

  def test_css_not_pseudo
    paras = @doc.css("p:not(.intro)")
    assert_equal 1, paras.length
    assert_equal "Second paragraph", paras.first.text
  end

  def test_css_multiple_selectors
    nodes = @doc.css("h1, p")
    assert_equal 3, nodes.length
  end

  def test_at_css
    h1 = @doc.at_css("h1")
    assert_equal "Hello World", h1.text
  end

  def test_node_name
    h1 = @doc.at_css("h1")
    assert_equal "h1", h1.name
  end

  def test_node_attributes
    div = @doc.at_css("#main")
    assert_equal "main",      div["id"]
    assert_equal "container", div["class"]
  end

  def test_node_children
    ul = @doc.at_css("ul")
    assert ul.children.length >= 3
  end

  def test_element_children
    ul = @doc.at_css("ul")
    assert_equal 3, ul.element_children.length
  end

  def test_parent
    h1 = @doc.at_css("h1")
    assert_equal "div", h1.parent.name
  end

  def test_next_sibling
    h1 = @doc.at_css("h1")
    sibling = h1.next_element
    assert_equal "p", sibling.name
    assert_equal "First paragraph", sibling.text
  end

  def test_text_content
    div = @doc.at_css("#main")
    assert_includes div.text, "Hello World"
    assert_includes div.text, "First paragraph"
  end

  def test_inner_html
    p = @doc.at_css("p.intro")
    assert_equal "First paragraph", p.inner_html
  end

  def test_to_html
    p = @doc.at_css("p.intro")
    assert_equal '<p class="intro">First paragraph</p>', p.to_html
  end

  def test_node_set_text
    paras = @doc.css("p")
    assert_equal "First paragraphSecond paragraph", paras.text
  end

  def test_node_set_each
    count = 0
    @doc.css("li").each { count += 1 }
    assert_equal 3, count
  end

  def test_node_set_map
    texts = @doc.css("li").map(&:text)
    assert_equal ["Item 1", "Item 2", "Item 3"], texts
  end
end

class XmlParserTest < Minitest::Test
  def setup
    xml = <<~XML
      <?xml version="1.0" encoding="UTF-8"?>
      <root>
        <items>
          <item id="1" category="a">First</item>
          <item id="2" category="b">Second</item>
          <item id="3" category="a">Third</item>
        </items>
        <meta key="version" value="1.0"/>
      </root>
    XML
    @doc = Nokogiri::XML(xml)
  end

  def test_parse_returns_xml_document
    assert_kind_of Nokogiri::XML::Document, @doc
  end

  def test_root_element
    assert_equal "root", @doc.root.name
  end

  def test_css_selector
    items = @doc.css("item")
    assert_equal 3, items.length
  end

  def test_css_attribute_selector
    category_a = @doc.css("item[category='a']")
    assert_equal 2, category_a.length
  end

  def test_xpath_descendant
    items = @doc.xpath("//item")
    assert_equal 3, items.length
  end

  def test_xpath_attribute_predicate
    items = @doc.xpath("//item[@category='a']")
    assert_equal 2, items.length
  end

  def test_xpath_child
    items = @doc.xpath("/root/items/item")
    assert_equal 3, items.length
  end

  def test_xpath_text
    texts = @doc.xpath("//item/text()")
    assert_equal 3, texts.length
  end

  def test_xpath_position
    first = @doc.xpath("//item[1]")
    assert_equal 1, first.length
    assert_equal "First", first.first.text
  end

  def test_xpath_attribute_axis
    ids = @doc.xpath("//item/@id")
    assert_equal 3, ids.length
  end

  def test_self_closing_element
    meta = @doc.at_css("meta")
    assert_equal "1.0", meta["value"]
  end
end

class DomManipulationTest < Minitest::Test
  def setup
    @doc = Nokogiri::HTML("<html><body><div id='container'><p>Hello</p></div></body></html>")
  end

  def test_add_child
    div = @doc.at_css("#container")
    span = @doc.create_element("span")
    span.content = "World"
    div.add_child(span)
    assert_equal 2, div.element_children.length
    assert_equal "World", div.at_css("span").text
  end

  def test_remove_node
    p = @doc.at_css("p")
    p.remove
    assert_nil @doc.at_css("p")
  end

  def test_set_attribute
    div = @doc.at_css("#container")
    div["data-new"] = "value"
    assert_equal "value", div["data-new"]
  end

  def test_create_text_node
    div = @doc.at_css("#container")
    text = @doc.create_text_node(" World")
    div.add_child(text)
    assert_includes div.text, "Hello"
    assert_includes div.text, " World"
  end

  def test_add_next_sibling
    p = @doc.at_css("p")
    span = @doc.create_element("span")
    span.content = "After"
    p.add_next_sibling(span)
    assert_equal "span", p.next_element.name
  end
end

class EntityDecodingTest < Minitest::Test
  def test_html_entities
    doc = Nokogiri::HTML("<p>Hello &amp; World &lt;3&gt;</p>")
    assert_equal "Hello & World <3>", doc.at_css("p").text
  end

  def test_numeric_entities
    doc = Nokogiri::HTML("<p>&#169; &#x263A;</p>")
    text = doc.at_css("p").text
    assert_includes text, "©"
    assert_includes text, "☺"
  end
end
