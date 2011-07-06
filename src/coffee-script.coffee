# CoffeeScript can be used both on the server, as a command-line compiler based
# on Node.js/V8, or to run CoffeeScripts directly in the browser. This module
# contains the main entry functions for tokenizing, parsing, and compiling
# source CoffeeScript into JavaScript.
#
# If included on a webpage, it will automatically sniff out, compile, and
# execute all scripts present in `text/coffeescript` tags.

fs               = require 'fs'
path             = require 'path'
vm               = require 'vm'
{Module}         = require 'module'
{Lexer,RESERVED} = require './lexer'
{parser}         = require './parser'

# TODO: Remove registerExtension when fully deprecated.
if require.extensions
  require.extensions['.coffee'] = (module, filename) ->
    content = compile fs.readFileSync(filename, 'utf8'), {filename}
    module._compile content, filename
else if require.registerExtension
  require.registerExtension '.coffee', (content) -> compile content

# The current CoffeeScript version number.
exports.VERSION = '1.1.1'

# Words that cannot be used as identifiers in CoffeeScript code
exports.RESERVED = RESERVED

# Expose helpers for testing.
exports.helpers = require './helpers'

# Compile a string of CoffeeScript code to JavaScript, using the Coffee/Jison
# compiler.
exports.compile = compile = (code, options = {}) ->
  try
    (parser.parse lexer.tokenize code).compile options
  catch err
    err.message = "In #{options.filename}, #{err.message}" if options.filename
    throw err

# Tokenize a string of CoffeeScript code, and return the array of tokens.
exports.tokens = (code, options) ->
  lexer.tokenize code, options

# Parse a string of CoffeeScript code or an array of lexed tokens, and
# return the AST. You can then compile it by calling `.compile()` on the root,
# or traverse it by using `.traverse()` with a callback.
exports.nodes = (source, options) ->
  if typeof source is 'string'
    parser.parse lexer.tokenize source, options
  else
    parser.parse source

# Compile and execute a string of CoffeeScript (on the server), correctly
# setting `__filename`, `__dirname`, and relative `require()`.
exports.run = (code, options) ->
  mainModule = require.main

  # Set the filename.
  mainModule.filename = process.argv[1] =
      if options.filename then fs.realpathSync(options.filename) else '.'

  # Clear the module cache.
  mainModule.moduleCache and= {}

  # Assign paths for node_modules loading
  if process.binding('natives').module
    {Module} = require 'module'
    mainModule.paths = Module._nodeModulePaths path.dirname options.filename

  # Compile.
  if path.extname(mainModule.filename) isnt '.coffee' or require.extensions
    mainModule._compile compile(code, options), mainModule.filename
  else
    mainModule._compile code, mainModule.filename

# Compile and evaluate a string of CoffeeScript (in a Node.js-like environment).
# The CoffeeScript REPL uses this to run the input.
exports.eval = (code, options = {}) ->
  return unless code = code.trim()
  sandbox = options.sandbox ? {}
  unless sandbox and sandbox.require
    sandbox.module = new Module('repl')
    sandbox.require = (path) -> Module._load path, sandbox.module
    sandbox.require[x] = require[x] for x of require
    sandbox.require.resolve = (request) -> Module._resolveFilename request, sandbox.module
    sandbox[g] = global[g] for g in Object.getOwnPropertyNames global
    sandbox.global = sandbox
    sandbox.global.global = sandbox.global.root = sandbox.global.GLOBAL = sandbox
    sandbox.global = sandbox
    sandbox.global.global = sandbox.global.root = sandbox.global.GLOBAL = sandbox
    sandbox.__filename = sandbox.module.filename = options.filename || 'eval'
    sandbox.__dirname  = path.dirname sandbox.__filename
  o = {}; o[k] = v for k, v of options
  o.bare = on # ensure return value
  js = compile "_=(#{code}\n)", o
  vm.runInNewContext js, sandbox, sandbox.__filename

# Instantiate a Lexer for our use here.
lexer = new Lexer

# The real Lexer produces a generic stream of tokens. This object provides a
# thin wrapper around it, compatible with the Jison API. We can then pass it
# directly as a "Jison lexer".
parser.lexer =
  lex: ->
    [tag, @yytext, @yylineno] = @tokens[@pos++] or ['']
    tag
  setInput: (@tokens) ->
    @pos = 0
  upcomingInput: ->
    ""

parser.yy = require './nodes'
