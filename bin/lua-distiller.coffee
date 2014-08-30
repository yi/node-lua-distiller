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
fs = require "fs"
## cli parameters
p.version(pkg.version)
  .option('-o, --output [VALUE]', 'output directory')
  .option('-n, --onlyKeepMinifiedFile', 'only keep minified file')
  .option('-i, --input [VALUE]', 'path to main entrance coffee file')
  .option('-x, --excludes [VALUE]', 'package names to be excluded, separated by: ","')
  .option('-m, --minify [type]', 'minify merged javascript file. [closure] use Closure Compiler, [uglify] use uglify-js2, [none] do not minify', 'closure')
  .parse(process.argv)

EXTNAME = ".lua"

COMMENT_MARK = "--"

BASE_FILE_PATH = ""

HR = "\n\n---------------------------------------\n\n\n"

DISTILLER_HEAD = """
if __DISTILLER == nil then
  __DISTILLER = nil
  __DISTILLER = {
    FACTORIES = { },
    __nativeRequire = require,
    require = function(id)
      assert(type(id) == "string", "require invalid id:" .. tostring(id))
      if package.loaded[id] then
        return package.loaded[id]
      end
      if __DISTILLER.FACTORIES[id] then
        local func = __DISTILLER.FACTORIES[id]
        package.loaded[id] = func(__DISTILLER.require) or true
        return package.loaded[id]
      end
      return __DISTILLER.__nativeRequire(id)
    end,
    define = function(self, id, factory)
      assert(type(id) == "string", "invalid id:" .. tostring(id))
      assert(type(factory) == "function", "invalid factory:" .. tostring(factory))
      assert(package.loaded[id] == nil and self.FACTORIES[id] == nil, "module " .. tostring(id) .. " is already defined")
      self.FACTORIES[id] = factory
    end,
    exec = function(self, id)
      local func = self.FACTORIES[id]
      assert(func, "missing factory method for id " .. tostring(id))
      func(__DISTILLER.require)
    end
  }
end

#{HR}
"""


# 要忽略包名
EXCLUDE_PACKAGE_NAMES = "cjson zlib pack socket lfs lsqlite3 Cocos2d Cocos2dConstants".split(" ")

path = require "path"
mkdirp = require "mkdirp"
_ = require "underscore"
child_process = require 'child_process'
debuglog = require('debug')('distill')

# 正则表达式匹配出 lua 代码中的 require 部分
RE_REQUIRE = /^.*require[\(\ ][\'"]([a-zA-Z0-9\.\_\/\-]+)[\'"]/mg

OUTPUT_FILE_PATH = ""

MODULES = {}

# 用于解决循环引用导致无限循环的问题
VISITED_PATH = {}

# 遇到错误时退出
quitWithError = (msg)->
  console.error "ERROR: #{msg}"
  process.exit 1

# 递归地从入口文件开始扫描所有依赖
scan = (filename, requiredBy) ->

  # 扫描文件中所有 require() 方法
  requiredBy or= p.input

  debuglog "scan: #{filename}, required by:#{requiredBy}"

  quitWithError "missing file at #{filename}, required by:#{requiredBy}" unless fs.existsSync(filename)

  code = fs.readFileSync filename, encoding : 'utf8'

  requires = []

  processedCode = code.replace RE_REQUIRE, (line, packageName, indexFrom, whole)->

    if packageName? and
    not VISITED_PATH["#{filename}->#{packageName}"] and       # 避免循环引用
    !~EXCLUDE_PACKAGE_NAMES.indexOf(packageName) and          # 避开的包
    (!~line.indexOf(COMMENT_MARK) and line.indexOf(COMMENT_MARK) < line.indexOf('require'))     # 忽略被注释掉的代码
      console.log "[lua-distiller] require #{packageName} in #{filename}"
      requires.push packageName
      VISITED_PATH["#{filename}->#{packageName}"] = true      # 添加到阅历中
      #return line.replace("require", "__DEFINED.__get")
      return line
    else

      console.log "[lua-distiller] ignore #{packageName} in #{filename}"
      # 是被注释掉的 require
      return line

  for module in requires

    #continue if ~EXCLUDE_PACKAGE_NAMES.indexOf(module)

    if MODULES[module]
      # 忽略已经被摘取的模块, 但要提高这个依赖模块的排名
      #MODULE_ORDERS.unshift module
      MODULE_ORDERS.push module
      continue

    pathToModuleFile = "#{module.replace(/\./g, '/')}.lua"
    pathToModuleFile = path.normalize(path.join(BASE_FILE_PATH, pathToModuleFile))

    # run recesively
    MODULES[module] = scan(pathToModuleFile, filename)

  return processedCode



##======= 以下为主体逻辑

## validate input parameters
quitWithError "missing main entrance coffee file (-i), use -h for help." unless p.input?

# validate input path
p.input = path.resolve process.cwd(), (p.input || '')
quitWithError "bad main entrance file: #{p.input}, #{path.extname(p.input)}." unless fs.existsSync(p.input) and path.extname(p.input) is EXTNAME
BASE_FILE_PATH = path.dirname p.input

if p.excludes
  EXCLUDE_PACKAGE_NAMES = EXCLUDE_PACKAGE_NAMES.concat(p.excludes.split(",").map((item)->item.trim()))

# figure out output path
p.output = path.resolve(process.cwd(), p.output || '')

if path.extname(p.output)
  OUTPUT_FILE_PATH = path.resolve process.cwd(), p.output
else
  outputBasename = path.basename(p.output ||  p.input, '.lua')
  OUTPUT_FILE_PATH = path.join p.output, "#{outputBasename}.merged.lua"

mkdirp.sync(path.dirname(OUTPUT_FILE_PATH))

## describe the job
console.log "lua-distiller v#{pkg.version}"
console.log "merge from #{path.relative(process.cwd(), p.input)} to #{path.relative(process.cwd(),OUTPUT_FILE_PATH)}"
console.log "ignore package: #{EXCLUDE_PACKAGE_NAMES}"

## scan modules
console.log "scanning..."
entranceName = path.basename(p.input, ".lua")
MODULES[entranceName] = scan(p.input)

console.log "scan complete, generate output to: #{OUTPUT_FILE_PATH}"

result = "-- Generated by node-lua-distiller(version: #{pkg.version})  at #{new Date}"

# 换行
result += HR

# 加头
result += DISTILLER_HEAD

# 把依赖打包进去
for moduleId, content of MODULES
  # 将 lua 实现代码加套 (function() end)() 的外壳然后注册到 __DEFINED 上去
  result += """
__DISTILLER:define("#{moduleId}", function(require)
#{content}
end)

#{HR}
"""

# 加入口代码块
result += """
__DISTILLER:exec("#{entranceName}")
"""


# 输出
fs.writeFileSync OUTPUT_FILE_PATH, result

