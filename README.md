# itonoko

Pure Ruby HTML/XML parser with nokogiri-compatible API. No native extensions, no libxml2 dependency.

## Installation

```ruby
# Gemfile
gem "itonoko"
```

```sh
gem install itonoko
```

## Usage

Drop-in compatible with nokogiri's core API:

```ruby
require "itonoko"

# HTML parsing
doc = Nokogiri::HTML(<<~HTML)
  <html>
    <body>
      <h1 id="title">Hello</h1>
      <ul>
        <li class="item">One</li>
        <li class="item active">Two</li>
        <li class="item">Three</li>
      </ul>
      <a href="https://example.com" data-track="nav">Link</a>
    </body>
  </html>
HTML

# CSS selectors
doc.css("li.item")               #=> NodeSet of 3
doc.css("li:nth-child(2)")       #=> NodeSet of 1
doc.css("a[data-track='nav']")   #=> NodeSet of 1
doc.css("li:not(.active)")       #=> NodeSet of 2
doc.at_css("#title").text        #=> "Hello"

# XPath
doc.xpath("//li")                         #=> NodeSet of 3
doc.xpath("//li[@class='active']")        #=> NodeSet of 1 (exact match)
doc.xpath("//a/@href")                    #=> attribute nodes

# Node navigation
node = doc.at_css(".active")
node.name           #=> "li"
node.text           #=> "Two"
node["class"]       #=> "item active"
node.parent.name    #=> "ul"
node.next_element.name   #=> "li"
node.previous_element.name #=> "li"

# DOM manipulation
node["data-new"] = "value"
node.add_child("<span>child</span>")
node.remove

# XML parsing
xml = Nokogiri::XML(<<~XML)
  <?xml version="1.0"?>
  <books>
    <book id="1" genre="fiction"><title>Dune</title></book>
    <book id="2" genre="nonfiction"><title>Cosmos</title></book>
  </books>
XML

xml.css("book[genre='fiction']").map { |n| n.at_css("title").text }
#=> ["Dune"]

xml.xpath("//book[@genre='nonfiction']/title/text()").map(&:text)
#=> ["Cosmos"]
```

## Supported Features

### CSS Selectors
| Selector | Example |
|---|---|
| Tag | `div` |
| Class | `.active` |
| ID | `#main` |
| Universal | `*` |
| Attribute (presence) | `[href]` |
| Attribute (exact) | `[type="text"]` |
| Attribute (prefix) | `[href^="https"]` |
| Attribute (suffix) | `[src$=".png"]` |
| Attribute (contains) | `[class*="btn"]` |
| Attribute (word) | `[class~="active"]` |
| Descendant | `div p` |
| Child | `ul > li` |
| Adjacent sibling | `h1 + p` |
| General sibling | `h1 ~ p` |
| `:first-child` / `:last-child` | `li:first-child` |
| `:nth-child(n)` | `tr:nth-child(odd)` |
| `:first-of-type` / `:last-of-type` | `p:first-of-type` |
| `:not()` | `li:not(.disabled)` |
| `:empty` / `:root` | `div:empty` |
| Multiple | `h1, h2, h3` |

### XPath (subset of 1.0)
- Axes: `child`, `parent`, `self`, `descendant`, `descendant-or-self`, `ancestor`, `following-sibling`, `preceding-sibling`, `attribute`
- Node tests: `tagname`, `*`, `text()`, `node()`, `comment()`
- Abbreviated: `//`, `.`, `..`, `@attr`
- Predicates: `[@attr]`, `[@attr='val']`, `[1]`, `[last()]`, `[position()>2]`
- Functions: `contains()`, `starts-with()`, `normalize-space()`, `not()`
- Union: `//a | //b`

## Benchmark

Compared against nokogiri 1.19.2 on Ruby 3.4.3 (arm64-darwin), 300 iterations:

| Task | itonoko | itonoko+YJIT | nokogiri | Ratio |
|---|---|---|---|---|
| HTML parse | 2.37ms | 1.96ms | 0.26ms | 9.1× |
| XML parse | 1.71ms | 1.46ms | 0.057ms | 30× |
| CSS tag selector | 2.49ms | 1.98ms | 0.28ms | 8.9× |
| CSS complex selector | 2.59ms | 2.03ms | 0.25ms | 10.3× |
| XPath `//book` | 1.99ms | 1.52ms | 0.091ms | 21.8× |
| NodeSet map | 2.58ms | 2.12ms | 0.27ms | 9.5× |

YJIT provides ~29% average speedup for itonoko. nokogiri uses libxml2 (C) so YJIT has minimal effect on it.

Run the benchmark yourself:

```sh
ruby bench/benchmark.rb          # without YJIT
ruby --yjit bench/benchmark.rb   # with YJIT
```

## When to use itonoko

**Use itonoko when:**
- Native extensions cannot be compiled (restricted environments, some CI setups)
- Bundling a standalone Ruby script with no C toolchain dependency
- Platforms where libxml2 is unavailable or hard to install

**Use nokogiri when:**
- Performance is critical
- Full HTML5 spec compliance is required
- You need complete XPath 1.0 / CSS4 coverage

## License

MIT
