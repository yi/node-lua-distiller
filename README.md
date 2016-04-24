# lua-distiller

 1. Merge multiple lua file into one single lua file by analyzing `require` dependencies
 2. (optional) Minify the merged lua file by [LuaSrcDiet](https://github.com/LuaDist/luasrcdiet)
 3. (optional) Compile both merged file and minified file into [luajit binary](http://luajit.org/)

分析 lua 代码中的 `require` 依赖，将分散的n个 lua 文件拼合成一个单一的 lua 文件

## Install 安装

```bash
npm install coffee-script lua-distiller -g
```

[LuaSrcDiet][] 是可选依赖。如果如果需要 minify 功能，
请确保 `LuaSrcDiet.lua` 在 `$PATH` 中。

[LuaSrcDiet]: https://github.com/LuaDist/luasrcdiet/tree/486129fa1ef1539071d14a366d686f3892c3d43f

## Usage 用法

Use in command line

```bash
lua-distill -i path/to/main.lua -o dist/dist.lua
```

## Command line options 命令行参数

```
  -h, --help                  output usage information
  -V, --version               output the version number
  -o, --output [VALUE]        output directory
  -n, --onlyKeepMinifiedFile  only keep minified file
  -i, --input [VALUE]         path to main entrance coffee file
  -x, --excludes [VALUE]      package names to be excluded, separated by: ","
  -m, --minify                minify merged lua file by LuaSrcDiet
  -j, --luajitify             compile merged lua file into luajit binary
```

## How it works 原理

这个工具采用和 [node-coffee-distiller](https://github.com/yi/node-coffee-distiller) 相同的工作原理，
用户给定一个入口文件，这个工具自动递归地分析入口文件中的依赖，然后将依赖和入口文件合并到一个输出结果。

### 这个工具派什么用?

当 lua 项目在一个完全嵌入的环境中被执行时，需要有一个方便发布快捷的生产环境发布部署载体。这个工具就是为了满足这个需求而设计的。

[类似的工具包括](http://stackoverflow.com/questions/9580366/keeping-everything-in-a-single-lua-bytecode-chunk) `luac -o`, `luajit`, [squish](http://matthewwild.co.uk/projects/squish/home), 但是这3个工具都需要手动维护合并列表，这无疑给始终在变化的项目增加了额外的工作量和出错的可能。

### 模拟 require

lua 的 `require` 实现是通过调用 `package.preload` 来确保一个模块只被加载一次。当分散的 lua 文件合并成一体之后，
不在存在外部需要 require 的文件，因此在合并的文件中采用模拟 require 的方式。

具体而言，使用一个全局变量 `__DEFINED` table 来保存所有合并入的依赖。
然后对每个被合并入的文件都使用 `(function() end)()` 来确保入口方法被执行前，被合并入的方法体已经完成自我的静态初始化。

### 优点
 1. 自动分析lua代码，无需手工维护合并列表
 2. 忽略被注释掉的 `require`
 3. 自动忽略项目中没有被用到的 lua 代码
 4. 可以嵌套地合并，比如一个项目中使用到n给第三方代码库，这些代码库都通过 distiller 合并过的话，将他们合并在一起不会产生冲突，是兼容的。

### 缺点
 1. 无法识别运行时程序拼合的模块名，比如 quick-x 中的 `require(cc.PACKAGE_NAME .. ".functions")` 是无法被识别的。并且我个人认为运行时拼合模块名是一种风险相对较大的实现，不推荐这样做。

## License

MIT

