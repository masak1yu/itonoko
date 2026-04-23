# frozen_string_literal: true
# Usage:
#   ruby bench/profile.rb [task]
#   task: all | html_parse | css | xpath | serialize (default: all)

$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)

require "stackprof"
require "itonoko/version"
require "itonoko/xml/attr"
require "itonoko/xml/node"
require "itonoko/xml/text"
require "itonoko/xml/node_set"
require "itonoko/xml/document"
require "itonoko/xml/document_fragment"
require "itonoko/html/document"
require "itonoko/html/document_fragment"
require "itonoko/parser/html_parser"
require "itonoko/parser/xml_parser"
require "itonoko/css/matcher"
require "itonoko/xpath/evaluator"

TASK = ARGV[0] || "all"
N    = 800

LARGE_HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="ja">
  <head><meta charset="UTF-8"><title>Profile Page</title></head>
  <body>
    <nav id="global-nav">
      <ul>
        #{(1..30).map { |i| %(<li class="nav-item #{i.odd? ? 'active' : ''}"><a href="/page/#{i}" data-id="#{i}">Page #{i}</a></li>) }.join("\n        ")}
      </ul>
    </nav>
    <main id="content">
      <article class="post featured" data-index="0">
        <h1 class="title">Featured Post &amp; More</h1>
        <div class="meta">
          <span class="author">Author &lt;Name&gt;</span>
          <time datetime="2024-01-01">January 1, 2024</time>
        </div>
        <div class="body">
          #{(1..15).map { |i| %(<p class="paragraph" id="p#{i}">Para #{i}: Lorem ipsum dolor sit amet &amp; consectetur adipiscing elit.</p>) }.join("\n          ")}
        </div>
        <ul class="tags">
          #{(1..15).map { |i| %(<li class="tag" data-id="#{i}" data-category="cat#{i % 3}">Tag #{i}</li>) }.join("\n          ")}
        </ul>
      </article>
      #{(1..15).map { |i|
        "<article class=\"post post-#{i}\" data-index=\"#{i}\">\n" \
        "  <h2><a href=\"/posts/#{i}\">Post #{i}</a></h2>\n" \
        "  <p class=\"summary\">Summary of post #{i} with some &amp; content.</p>\n" \
        "  <ul class=\"items\">\n" +
        (1..6).map { |j| "    <li class=\"item item-#{j % 2 == 0 ? 'even' : 'odd'}\"><a href=\"##{j}\">Item #{j}</a></li>" }.join("\n") +
        "\n  </ul>\n</article>"
      }.join("\n      ")}
    </main>
    <footer id="footer"><p>&copy; 2024 Profile Test.</p></footer>
  </body>
  </html>
HTML

LARGE_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <catalog>
    #{(1..80).map { |i|
      "<book id=\"bk#{i}\" category=\"#{%w[fiction nonfiction mystery thriller][i % 4]}\" year=\"#{2000 + i}\">" \
      "<title>Book Title #{i}</title>" \
      "<author first=\"Author\" last=\"#{i}\">Author #{i}</author>" \
      "<price>#{(9.99 + i * 0.5).round(2)}</price>" \
      "<description>Description for book #{i}.</description>" \
      "</book>"
    }.join("\n    ")}
  </catalog>
XML

def run_profile(name, n, &block)
  # warmup
  5.times { block.call }

  prof = StackProf.run(mode: :cpu, interval: 100, raw: true) do
    n.times { block.call }
  end

  out_path = File.expand_path("../../tmp/profile_#{name}.dump", __FILE__)
  FileUtils.mkdir_p(File.dirname(out_path))
  File.binwrite(out_path, Marshal.dump(prof))

  puts "\n#{'=' * 64}"
  puts "PROFILE: #{name}  (#{n} iterations)"
  puts "=" * 64
  StackProf::Report.new(prof).print_text(false, 30)

  prof
end

require "fileutils"

pre_parsed_html = Itonoko::HTML::Document.parse(LARGE_HTML)
pre_parsed_xml  = Itonoko::XML::Document.parse(LARGE_XML)

if TASK == "all" || TASK == "html_parse"
  run_profile("html_parse", N) do
    Itonoko::HTML::Document.parse(LARGE_HTML)
  end
end

if TASK == "all" || TASK == "xml_parse"
  run_profile("xml_parse", N) do
    Itonoko::XML::Document.parse(LARGE_XML)
  end
end

if TASK == "all" || TASK == "css"
  run_profile("css_tag", N) do
    pre_parsed_html.css("p")
  end

  run_profile("css_class", N) do
    pre_parsed_html.css(".nav-item")
  end

  run_profile("css_complex", N) do
    pre_parsed_html.css("article.post h2 a")
  end

  run_profile("css_attr", N) do
    pre_parsed_html.css("li[data-id]")
  end

  run_profile("css_nth", N) do
    pre_parsed_html.css("li:nth-child(odd)")
  end
end

if TASK == "all" || TASK == "xpath"
  run_profile("xpath_descendant", N) do
    pre_parsed_xml.xpath("//book")
  end

  run_profile("xpath_predicate", N) do
    pre_parsed_xml.xpath("//book[@category='fiction']")
  end

  run_profile("xpath_text", N) do
    pre_parsed_xml.xpath("//book/title/text()")
  end
end

if TASK == "all" || TASK == "serialize"
  node = pre_parsed_html.at_css("article.featured")

  run_profile("to_html", N) do
    node.to_html
  end

  run_profile("node_text", N) do
    pre_parsed_html.root.text
  end
end

puts "\n\nDump files written to tmp/profile_*.dump"
puts "Flamegraph: stackprof --flamegraph tmp/profile_<name>.dump | stackprof --flamegraph-viewer"
puts "or: stackprof tmp/profile_<name>.dump --text --limit 20"
