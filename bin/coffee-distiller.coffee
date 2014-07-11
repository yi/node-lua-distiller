#!/usr/bin/env coffee

##
# coffee-distiller
# https://github.com/yi/node-coffee-distiller
#
# Copyright (c) 2014 yi
# Licensed under the MIT license.
##

pkg = require "../package"
p = require "commander"
## cli parameters
p.version(pkg.version)
  .option('-o, --output [VALUE]', 'output directory')
  .option('-n, --onlyKeepMinifiedFile', 'only keep minified file')
  .option('-i, --input [VALUE]', 'path to main entrance coffee file')
  .option('-m, --minify [type]', 'minify merged javascript file. [closure] use Closure Compiler, [uglify] use uglify-js2, [none] do not minify', 'closure')
  .parse(process.argv)

# {{{ AMD 模版
AMD_TMPL = '''
## Module dependencies
__nativePath = require "path"
# NativeModule = require "native_module"

# A hack to fix requiring external module issue
__nativeRequire = require
__module = require "module"
__hackRequire = (id) -> __module._load id, module
# A hack to make cluster work
# cluster = NativeModule.require 'cluster'
__nativeCluster = require 'cluster'
__nativeCluster.settings.exec = "_third_party_main"
if process.env.NODE_UNIQUE_ID
  __nativeCluster._setupWorker()
  # Make sure it's not accidentally inherited by child processes.
  delete process.env.NODE_UNIQUE_ID

# A cache object contains all modules with their ids
__MODULES_BY_ID = {}

# Internal module class holding module id, dependencies and exports
class Module

  constructor: (@id, @factory) ->
    # Append module to cache
    __MODULES_BY_ID[@id] = this

  # Initialize exports
  initialize: ->
    @exports = {}
    # Imports a module
    @require or= (id) =>
      # If this is a relative path
      if id.charAt(0) == "."
        # Resolve id to absolute path
        id = __nativePath.normalize(__nativePath.join(__nativePath.dirname(@id), id))
        mod = __MODULES_BY_ID[id]
        throw new Error("module #{id} is not found") unless mod
        return mod.exports if mod.exports?
        mod.initialize()
      else
        __hackRequire id
    @factory.call this, @require, @exports, this
    @exports

# Define a module.
define = (id, factory) ->
  throw new Error("id must be specifed") unless id
  throw new Error("module #{id} is already defined") if id of __MODULES_BY_ID
  new Module(id, factory)

# Start a module
exec = (id) ->
  module = __MODULES_BY_ID[id]
  module.initialize()
'''
# }}}

path = require "path"
fs = require "fs"
mkdirp = require "mkdirp"
_ = require "underscore"
#async = require "async"
child_process = require 'child_process'
debug = require('debug')('distill')

DEFINE_HEAD = "\ndefine '%s', (require, exports, module) ->\n"

EXEC_TAIL = "\nexec '%s'"

RE_REQUIRE = /^.*require[\(\ ][\'"]([a-zA-Z0-9\.\_\/\-]+)[\'"]/mg

RE_HEAD = /^/mg

OUTPUT_JS_FILE = ""

OUTPUT_MINIFIED_JS_FILE = ""

OUTPUT_COFFEE_FILE = ""

PATH_TO_UGLIFY = path.resolve(__dirname, "../node_modules/uglify-js2/bin/uglifyjs2")

MODULES = {}

quitWithError = (msg)->
  console.error "ERROR: #{msg}"
  process.exit 1

scan = (filename, isMain=false, source) ->
  # 扫描文件中所有 require() 方法

  debug "scan: #{filename} (required by: #{source or 'Root'})"

  if not fs.existsSync(filename) and path.basename(filename) isnt "index.coffee"
    # in case node require "/path/to/dir"
    oldFilename = filename
    filename = filename.replace(".coffee", "/index.coffee")
    console.warn "WARNING: missing coffee file at #{oldFilename}, try #{filename} (required by: #{source or 'Root'})"

  unless fs.existsSync(filename)
    quitWithError "missing coffee file at #{filename} (required by: #{source or 'Root'})"

  code = fs.readFileSync filename,
    encoding : 'utf8'

  MODULES[filename] =
    id : filename
    code : code
    isMain : isMain

  requires = []

  code.replace RE_REQUIRE, ($0, $1)->
    requires.push $1 if $1? and (!~$0.indexOf('#') and  $0.indexOf('#') < $0.indexOf('require'))
    arguments[arguments.length - 1] = null
    #console.dir arguments

  #requires = code.match(RE_REQUIRE) || []
  #console.dir requires

  for module in requires

    # ignore module require
    continue unless module.charAt(0) is "."

    module = resolve(filename, module)

    # ignore included modules
    continue if MODULES[module ]

    # run recesively
    scan module, false, filename

  return

# 将相对路径解析成决定路径
resolve = (base, relative) ->
  return path.normalize(path.join(path.dirname(base), relative)) + ".coffee"

# 合并成一个文件
merge = ->

  result = "#{AMD_TMPL}\n\n"

  for id, module of MODULES
    #console.dir module
    id = id.replace('.coffee', '')
    result  += DEFINE_HEAD.replace('%s', id)
    result  += module.code.replace(RE_HEAD, '  ')
    result  += " \n"

  result  += EXEC_TAIL.replace('%s', p.input.replace('.coffee', ''))
  fs.writeFileSync(OUTPUT_COFFEE_FILE, result)

## validate input parameters
unless p.input?
  quitWithError "missing main entrance coffee file (-i), use -h for help."

p.input = path.resolve process.cwd(), (p.input || '')

unless fs.existsSync(p.input) and path.extname(p.input) is '.coffee'
  quitWithError "bad main entrance file: #{p.input}, #{path.extname(p.input)}."

p.output = path.resolve(process.cwd(), p.output || '')

if path.extname(p.output)
  outputBasename = path.basename(p.output, path.extname(p.output))
  OUTPUT_JS_FILE = path.join path.dirname(p.output), "#{outputBasename}.js"
  OUTPUT_MINIFIED_JS_FILE = path.join path.dirname(p.output), "#{outputBasename}.min.js"
  OUTPUT_COFFEE_FILE = path.join path.dirname(p.output), "#{outputBasename}.coffee"
else
  outputBasename = path.basename(p.input, '.coffee')
  OUTPUT_JS_FILE = path.join p.output, "#{outputBasename}.js"
  OUTPUT_MINIFIED_JS_FILE = path.join p.output, "#{outputBasename}.min.js"
  OUTPUT_COFFEE_FILE = path.join p.output, "#{outputBasename}.coffee"

mkdirp.sync(path.dirname(OUTPUT_JS_FILE))

## describe the job
console.log "[coffee-distiller] merge from #{path.relative(process.cwd(), p.input)} to #{path.relative(process.cwd(),OUTPUT_JS_FILE)}, minify via #{p.minify}"

## scan modules
console.log "[coffee-distiller] scanning..."
scan(p.input)

console.log "[coffee-distiller] merging #{_.keys(MODULES).length} coffee files..."
merge()

console.log "[coffee-distiller] compile coffee to js..."
child_process.exec "coffee -c #{OUTPUT_COFFEE_FILE}", (err, stdout, stderr)->
  if err?
    quitWithError "coffee compiler failed. error:#{err}, stdout:#{stdout}, stderr:#{stderr}"
    return

  console.log "[coffee-distiller] merging complete! #{path.relative(process.cwd(), OUTPUT_JS_FILE)}"

  switch p.minify
    when "none" then process.exit()
    when "uglify" then command = "#{PATH_TO_UGLIFY} #{OUTPUT_JS_FILE} -o #{OUTPUT_MINIFIED_JS_FILE}"
    else command = "java -jar #{__dirname}/compiler.jar --js #{OUTPUT_JS_FILE} --js_output_file #{OUTPUT_MINIFIED_JS_FILE} --compilation_level SIMPLE_OPTIMIZATIONS "

  console.log "[coffee-distiller] minifying js..."

  #child_process.exec "java -jar #{__dirname}/compiler.jar --js #{OUTPUT_JS_FILE} --js_output_file #{OUTPUT_MINIFIED_JS_FILE} --compilation_level SIMPLE_OPTIMIZATIONS ", (err, stdout, stderr)->
  child_process.exec command, (err, stdout, stderr)->
    if err?
      quitWithError "minify js failed. error:#{err}, stdout:#{stdout}, stderr:#{stderr}"
      return

    console.log "[coffee-distiller] minifying complete! #{path.relative(process.cwd(), OUTPUT_MINIFIED_JS_FILE)}"

    if p.onlyKeepMinifiedFile
      fs.unlinkSync OUTPUT_JS_FILE
      fs.unlinkSync OUTPUT_COFFEE_FILE
      console.log "[coffee-distiller] clean output files exept minified one"


