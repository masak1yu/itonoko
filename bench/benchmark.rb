# frozen_string_literal: true

# Usage:
#   ruby bench/benchmark.rb             # without YJIT
#   ruby --yjit bench/benchmark.rb      # with YJIT
#
# Runs itonoko and nokogiri in separate subprocesses to avoid namespace conflicts.

require "benchmark"
require "json"
require "tempfile"

LIB_DIR = File.expand_path("../../lib", __FILE__)

LARGE_HTML = <<~HTML
  <!DOCTYPE html>
  <html lang="ja">
  <head>
    <meta charset="UTF-8">
    <title>Benchmark Page</title>
  </head>
  <body>
    <nav id="global-nav">
      <ul>
        #{(1..20).map { |i| %(<li class="nav-item #{i.odd? ? 'active' : ''}"><a href="/page/#{i}">Page #{i}</a></li>) }.join("\n        ")}
      </ul>
    </nav>
    <main id="content">
      <article class="post featured">
        <h1 class="title">Featured Post</h1>
        <div class="meta">
          <span class="author">Author</span>
          <time datetime="2024-01-01">January 1, 2024</time>
        </div>
        <div class="body">
          #{(1..10).map { |i| %(<p class="paragraph p#{i}">Para #{i}: Lorem ipsum dolor sit amet consectetur adipiscing.</p>) }.join("\n          ")}
        </div>
        <div class="tags">
          #{(1..10).map { |i| %(<span class="tag" data-id="#{i}">Tag #{i}</span>) }.join("\n          ")}
        </div>
      </article>
      #{(1..10).map { |i|
        "<article class=\"post post-#{i}\" data-index=\"#{i}\">\n" \
        "  <h2><a href=\"/posts/#{i}\">Post #{i}</a></h2>\n" \
        "  <p>Summary of post #{i}.</p>\n" \
        "  <ul>\n" +
        (1..5).map { |j| "    <li class=\"item\">Item #{j}</li>" }.join("\n") +
        "\n  </ul>\n</article>"
      }.join("\n      ")}
    </main>
    <footer id="footer"><p>&copy; 2024 Benchmark.</p></footer>
  </body>
  </html>
HTML

LARGE_XML = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <catalog>
    #{(1..50).map { |i|
      "<book id=\"bk#{i}\" category=\"#{i.odd? ? 'fiction' : 'nonfiction'}\">" \
      "<title>Book #{i}</title><author>Author #{i}</author>" \
      "<price>#{(9.99 + i * 0.5).round(2)}</price></book>"
    }.join("\n    ")}
  </catalog>
XML

N = 300

BENCH_SCRIPT = <<~'RUBY'
  # frozen_string_literal: true
  require "benchmark"
  require "json"

  LIB = ENV["LIB"]
  N   = ENV["N"].to_i

  if ENV["ENGINE"] == "itonoko"
    $LOAD_PATH.unshift(LIB)
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
    HD = Itonoko::HTML::Document
    XD = Itonoko::XML::Document
  else
    require "nokogiri"
    HD = Nokogiri::HTML::Document
    XD = Nokogiri::XML::Document
  end

  HTML_SRC = ENV["HTML_FILE"] ? File.read(ENV["HTML_FILE"]) : ""
  XML_SRC  = ENV["XML_FILE"]  ? File.read(ENV["XML_FILE"])  : ""

  tasks = {
    "HTML parse"         => -> { HD.parse(HTML_SRC) },
    "XML parse"          => -> { XD.parse(XML_SRC) },
    "CSS tag"            => -> { HD.parse(HTML_SRC).css("p") },
    "CSS class"          => -> { HD.parse(HTML_SRC).css(".nav-item") },
    "CSS complex"        => -> { HD.parse(HTML_SRC).css("article.post h2 a") },
    "CSS attr"           => -> { HD.parse(HTML_SRC).css("span[data-id]") },
    "CSS :nth-child"     => -> { HD.parse(HTML_SRC).css("li:nth-child(odd)") },
    "XPath //book"       => -> { XD.parse(XML_SRC).xpath("//book") },
    "XPath predicate"    => -> { XD.parse(XML_SRC).xpath("//book[@category='fiction']") },
    "XPath text()"       => -> { XD.parse(XML_SRC).xpath("//book/title/text()") },
    "NodeSet map"        => -> { HD.parse(HTML_SRC).css("li").map(&:text) },
    "to_html"            => -> { HD.parse(HTML_SRC).css("article.featured, article.post").first&.to_html },
  }

  results = {}
  tasks.each do |name, task|
    # warm up
    3.times { task.call }
    t = Benchmark.realtime { N.times { task.call } }
    results[name] = (t / N * 1000).round(4)  # ms per iteration
  end

  puts JSON.generate(results)
RUBY

RUBY_BIN = RbConfig.ruby  # full path to current Ruby interpreter

def run_engine(engine, html_file, xml_file, yjit: false)
  script = Tempfile.new(["bench_", ".rb"])
  script.write(BENCH_SCRIPT)
  script.flush

  ruby_flags = yjit ? "--yjit" : "--disable-yjit"
  env = {
    "ENGINE"    => engine,
    "LIB"       => LIB_DIR,
    "N"         => N.to_s,
    "HTML_FILE" => html_file,
    "XML_FILE"  => xml_file,
  }

  env_str = env.map { |k, v| "#{k}=#{v.shellescape}" }.join(" ")
  cmd = "#{RUBY_BIN.shellescape} #{ruby_flags} -I#{LIB_DIR.shellescape} #{script.path}"
  output = `env #{env_str} #{cmd} 2>/dev/null`
  JSON.parse(output)
rescue => e
  $stderr.puts "  #{engine} failed: #{e.message}"
  {}
ensure
  script.close
  script.unlink
end

require "shellwords"

# Write temp files for HTML and XML
html_file = Tempfile.new(["bench_html_", ".html"])
html_file.write(LARGE_HTML)
html_file.flush

xml_file = Tempfile.new(["bench_xml_", ".xml"])
xml_file.write(LARGE_XML)
xml_file.flush

yjit_available = system("ruby --yjit -e 'RubyVM::YJIT.enabled?' > /dev/null 2>&1")

puts "=" * 72
puts "Benchmark: itonoko (pure Ruby) vs nokogiri (C/libxml2)"
puts "Ruby: #{RUBY_VERSION} #{RUBY_PLATFORM}"
puts "YJIT available: #{yjit_available}"
puts "Iterations: #{N} per task"
puts "=" * 72
puts

print "Running itonoko (no YJIT)...  "
ito_no_yjit = run_engine("itonoko", html_file.path, xml_file.path, yjit: false)
puts "done"

print "Running itonoko (YJIT)...     "
ito_yjit = yjit_available ? run_engine("itonoko", html_file.path, xml_file.path, yjit: true) : {}
puts yjit_available ? "done" : "skipped"

print "Running nokogiri (no YJIT)... "
noko_no_yjit = run_engine("nokogiri", html_file.path, xml_file.path, yjit: false)
puts "done"

print "Running nokogiri (YJIT)...    "
noko_yjit = yjit_available ? run_engine("nokogiri", html_file.path, xml_file.path, yjit: true) : {}
puts yjit_available ? "done" : "skipped"

html_file.close; html_file.unlink
xml_file.close;  xml_file.unlink

puts
puts "Results (ms/iteration — lower is better):"
puts

header = "%-20s %12s %12s %12s %12s %12s" % [
  "Task",
  "ito (no YJIT)",
  "ito (YJIT)",
  "noko (no YJIT)",
  "noko (YJIT)",
  "ratio (no YJIT)"
]
puts header
puts "-" * header.length

tasks = (ito_no_yjit.keys + noko_no_yjit.keys).uniq
tasks.each do |task|
  ito_val  = ito_no_yjit[task]
  ito_y    = ito_yjit[task]
  noko_val = noko_no_yjit[task]
  noko_y   = noko_yjit[task]

  ratio = (ito_val && noko_val && noko_val > 0) ? (ito_val / noko_val).round(1) : nil
  ratio_str = ratio ? "#{ratio}x slower" : "N/A"

  row = "%-20s %12s %12s %12s %12s %12s" % [
    task,
    ito_val  ? "#{ito_val}ms"  : "N/A",
    ito_y    ? "#{ito_y}ms"    : "N/A",
    noko_val ? "#{noko_val}ms" : "N/A",
    noko_y   ? "#{noko_y}ms"  : "N/A",
    ratio_str,
  ]
  puts row
end

puts
puts "Notes:"
puts "  - itonoko: pure Ruby, no native extensions"
puts "  - nokogiri: wraps libxml2 via C extension"
puts "  - YJIT speedup = ito(no YJIT) / ito(YJIT)"
if yjit_available && !ito_yjit.empty? && !ito_no_yjit.empty?
  speedups = ito_no_yjit.filter_map do |k, v|
    y = ito_yjit[k]
    y && y > 0 ? (v / y).round(2) : nil
  end
  avg = (speedups.sum / speedups.size).round(2) unless speedups.empty?
  puts "  - Average YJIT speedup for itonoko: #{avg}x" if avg
end
