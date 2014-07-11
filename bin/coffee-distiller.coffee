#!/usr/bin/env coffee

##
# lua-distiller
# https://github.com/yi/node-lua-distiller
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

EXTNAME = ".lua"

COMMENT_MARK = "--"

# {{{ AMD 模版
AMD_TMPL = '''
__DEFINED = __DEFINED or {
  __get = function(id)
    assert(id, "__DEFINED.__get() failed. invalid id:"..tostring(id))
    assert(__DEFINED and __DEFINED[id], "__DEFINED.__get() failed. missing module:"..tostring(id))
    return __DEFINED[id]
  end
}
'''
# }}}

path = require "path"
fs = require "fs"
mkdirp = require "mkdirp"
_ = require "underscore"
#async = require "async"
child_process = require 'child_process'
debuglog = require('debug')('distill')

DEFINE_HEAD = "\ndefine '%s', (require, exports, module) ->\n"

EXEC_TAIL = "\nexec '%s'"

RE_REQUIRE = /^.*require[\(\ ][\'"]([a-zA-Z0-9\.\_\/\-]+)[\'"]/mg

RE_HEAD = /^/mg

OUTPUT_JS_FILE = ""

PATH_TO_UGLIFY = path.resolve(__dirname, "../node_modules/uglify-js2/bin/uglifyjs2")

MODULES = {}
MODULE_ORDERS = []

quitWithError = (msg)->
  console.error "ERROR: #{msg}"
  process.exit 1

scan = (filename, requiredBy) ->
  # 扫描文件中所有 require() 方法
  requiredBy or= p.input

  debuglog "scan: #{filename}, required by:#{requiredBy}"

  unless fs.existsSync(filename)
    quitWithError "missing coffee file at #{filename}, required by:#{requiredBy}"

  code = fs.readFileSync filename, encoding : 'utf8'

  MODULES[filename] =
    id : filename
    code : code
    isMain : isMain

  requires = []

  processedCode = code.replace RE_REQUIRE, (line, packageName, indexFrom, whole)->

    #debuglog "================================="
    #console.dir arguments
    #debuglog "[re] line:#{line}, packageName:#{packageName}"

    if packageName? and (!~line.indexOf(COMMENT_MARK) and line.indexOf(COMMENT_MARK) < line.indexOf('require'))
      #debuglog "[ADD] %%%%%%%%%%%%%%%%%%%%%%% \n\n\n"
      requires.push packageName
      return line.replace("require", "__DEFINED.__get")
    else
      # 是被注释掉的 require
      return line

  debuglog "%%%%%%%%%%%%%%%%%%%%%%%a"
  debuglog processedCode
  debuglog "%%%%%%%%%%%%%%%%%%%%%%%d"

  for module in requires

    # ignore module require
    continue if MODULES[module]

    filename = resolve(module)

    # run recesively
    MODULES[module] = scan(module, filename)

  return processedCode

# 将相对路径解析成决定路径
resolve = (base, relative) ->
  return path.normalize(path.join(path.dirname(base), relative)) + ".lua"

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
  fs.writeFileSync(OUTPUT_JS_FILE, result)





## validate input parameters
unless p.input?
  quitWithError "missing main entrance coffee file (-i), use -h for help."

p.input = path.resolve process.cwd(), (p.input || '')

unless fs.existsSync(p.input) and path.extname(p.input) is EXTNAME
  quitWithError "bad main entrance file: #{p.input}, #{path.extname(p.input)}."

p.output = path.resolve(process.cwd(), p.output || '')

if path.extname(p.output)
  outputBasename = path.basename(p.output, path.extname(p.output))
  OUTPUT_JS_FILE = path.join path.dirname(p.output), "#{outputBasename}.lua"
else
  outputBasename = path.basename(p.input, '.coffee')
  OUTPUT_JS_FILE = path.join p.output, "#{outputBasename}.lua"

mkdirp.sync(path.dirname(OUTPUT_JS_FILE))

## describe the job
console.log "[lua-distiller] merge from #{path.relative(process.cwd(), p.input)} to #{path.relative(process.cwd(),OUTPUT_JS_FILE)}, minify via #{p.minify}"

## scan modules
console.log "[lua-distiller] scanning..."
scan(p.input)

debuglog "scan complete"



#console.log "[lua-distiller] merging #{_.keys(MODULES).length} coffee files..."
#merge()

