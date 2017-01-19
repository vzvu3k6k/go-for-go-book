require 'asciidoctor'
require 'asciidoctor/extensions'
require 'pathname'
require 'json'
require 'digest'
require 'uri'
require 'net/http'

CACHE_DIR    = Pathname.new('./.cache')
EXAMPLES_DIR = Pathname.new('./examples')

CONFIG     = JSON.parse(File.read('config.json'))
GO_VERSION = CONFIG['Versions']['Go']

def run_cached(kind, command, file = nil)
  cache_file = Pathname.new(CACHE_DIR+"#{kind}-#{GO_VERSION}"+(file || command.gsub(/[^\w.]/, '_')))
  cache_mtime = cache_file.mtime rescue Time.new(0)
  content = if !File.exist?(cache_file) || file && cache_mtime < file.mtime
    STDERR.puts "macro: #{command}"
    c = %x(#{command})
    cache_file.parent.mkpath
    cache_file.write(c)
    c
  else
    cache_file.read
  end
end

# ref: http://asciidoctor.org/docs/user-manual/#block-macro-processor-example

# Expands to an example code under ./examples or its output
# TODO: place a link to Go playground
#
#   goexample::parsefile[]
#   goexample::parsefile[output]
#
# Runs examples/parseexpr/parseexpr.go
class GoExampleMacro < Asciidoctor::Extensions::BlockMacroProcessor
  use_dsl

  named :goexample

  def process(parent, target, attrs)
    filename = attrs['file'] || "#{target}.go"
    file = EXAMPLES_DIR + "#{target}/#{filename}"
    style = attrs.delete(1)

    if style === 'output'
      content = run_cached('go-run', "go run #{file} 2>&1", file)
      create_listing_block(
        parent,
        content,
        attrs
      )
    else
      source = IO.read(file)
      digest = Digest::SHA1.hexdigest(source)

      playground_keys_file = EXAMPLES_DIR + 'playground_keys.json'
      playground_keys = JSON.parse(File.read(playground_keys_file))

      playground_key = playground_keys[digest]
      unless playground_key
        # quick check if the example contains non-standard package or not
        if /\./ === %x(go list -f {{.Imports}} #{file}) # we know that file starts with ./
          # nop
        else
          uri = URI('https://playground.golang.org/share')
          Net::HTTP.start(uri.host, uri.port) do |http|
            STDERR.print "macro: sharing #{file} to playground ... "

            req = Net::HTTP::Post.new uri
            req.body = source
            req['Content-Type'] = 'text/plain'

            resp = http.request req

            STDERR.puts "#{resp.code} #{resp.message}"
            if 200 <= resp.code && resp.code < 300
              playground_keys[digest] = playground_key = resp.body.chomp
              File.open(playground_keys_file, 'w') do |f|
                f.puts playground_keys.to_json
              end
            end
          end rescue nil
        end
      end

      block = create_listing_block(
        parent,
        source.gsub("\t", '    '),
        attrs.merge({
          'style'    => 'source',
          'language' => 'go',
          'title'    => filename,
        })
      )
      block.title = filename
      block.assign_caption
      block
    end
  end
end

# Expands to `go doc` output
#
#   godoc::go/ast.Print[]
class GoDocMacro < Asciidoctor::Extensions::BlockMacroProcessor
  use_dsl

  named :godoc

  def process(parent, target, attrs)
    m = %r<^((?:[\w.]+/)*\w+)\.([\w.]+)$>.match(target)
    opts = attrs.delete(1) || ''

    pkg, entry = m[1], m[2]
    if /^[a-z]/ === entry
      opts += ' -u'
    end
    godoc = run_cached('go-doc', "go doc #{opts} #{target}")
    godoc.sub!(/\n\n\n.*$/m, '')
    decl, *doc = godoc.split(/^ {4}/)
    decl_block = create_listing_block(
      parent,
      decl.gsub("\t", '    ').lines.map(&:chomp),
      attrs.merge({
        'style'    => 'source',
        'language' => 'go',
        'title'    => "godoc: http://godoc.org/pkg/#{pkg}##{entry}[#{target}]",
      })
    )
    # TODO doc
    decl_block
  end
end

class GoSourceMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :gosource

  def process(parent, target, attrs)
    ref = attrs.delete(1)
    text = target.sub(%r(^.+/), '').sub('#L', ':')
    create_anchor(parent, "<code>#{text}</code>", { type: :link, target: %(https://github.com/golang/go/blob/#{ref}/#{target}) }.merge(attrs)).convert
  end
end

class TermMacro < Asciidoctor::Extensions::InlineMacroProcessor
  use_dsl

  named :term

  def process parent, target, attrs
    if parent.document.attributes['backend'] == 'pdf'
      %(#{target}（#{attrs[1]}）)
    else
      %(#{target}（<dfn>#{attrs[1]}</dfn>）)
    end
  end
end

class SetAttributesPreprocessor < Asciidoctor::Extensions::Preprocessor
  def process document, reader
    document.attributes['go_version'] = GO_VERSION
    document.attributes['revnumber'] = %x(git describe --tags --always HEAD).chomp
    document.attributes['revdate'] = %x(git log -1 --pretty=%aI).chomp
    reader
  end
end

Asciidoctor::Extensions.register do
  block_macro  GoExampleMacro
  block_macro  GoDocMacro
  inline_macro GoSourceMacro
  inline_macro TermMacro
  preprocessor SetAttributesPreprocessor

  if @document.basebackend?('html') && @document.attributes['backend'] != 'pdf' && ENV['PRODUCTION']
    postprocessor do
      process do |doc, output|
        output
          .sub('</html>', <<-GA_HTML)
<script>
  (function(i,s,o,g,r,a,m){i['GoogleAnalyticsObject']=r;i[r]=i[r]||function(){
  (i[r].q=i[r].q||[]).push(arguments)},i[r].l=1*new Date();a=s.createElement(o),
  m=s.getElementsByTagName(o)[0];a.async=1;a.src=g;m.parentNode.insertBefore(a,m)
  })(window,document,'script','//www.google-analytics.com/analytics.js','ga');
  ga('create', 'UA-34276254-7', 'auto');
  ga('send', 'pageview');
</script>
</html>
        GA_HTML
      end
    end
  end

  if @document.basebackend?('html') && @document.attributes['backend'] != 'pdf'
    postprocessor do
      process do |doc, output|
        output
          .sub('</head>', <<-JAVASCRIPT.chomp)
<script>
if (/\.github\.io$/.test(location.host) && location.protocol === 'http:') {
  location.protocol = 'https:';
}
</script>
</head>
          JAVASCRIPT
          .sub('</style>', <<-STYLE.chomp)
body{word-break:break-word;}
</style>
          STYLE
      end
    end
  end
end
