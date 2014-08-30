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
