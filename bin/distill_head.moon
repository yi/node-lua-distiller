if __DISTILLER == nil
  export __DISTILLER = nil
  __DISTILLER =

    FACTORIES: {}

    __nativeRequire: require

    --  console.dir package.loaded["models.player"]
    require: (id)->
      assert type(id) == "string", "require invalid id:#{id}"
      return package.loaded[id] if package.loaded[id]

      if __DISTILLER.FACTORIES[id]
        -- source in factory
        func = __DISTILLER.FACTORIES[id]
        package.loaded[id] = func(__DISTILLER.require) or true
        return package.loaded[id]

      return __DISTILLER.__nativeRequire(id)

    define: (id, factory) =>
      assert type(id) == "string", "invalid id:#{id}"
      assert type(factory) == "function", "invalid factory:#{factory}"
      if package.loaded[id] == nil and @FACTORIES[id] == nil
        @FACTORIES[id] = factory
      else
        print "[__DISTILLER::define] module #{id} is already defined"
      return

    exec: (id)=>
      func = @FACTORIES[id]
      assert func, "missing factory method for id #{id}"
      func(__DISTILLER.require)
      return


