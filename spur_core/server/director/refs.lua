-- Every reference to a placed thing, variable or card in a scenario, walked in one place.
-- The editor does the same walk in html/js/director/refs.js.

DirectorRefs = {}

--- Visit each value a path names in `obj`. A path is dotted keys; `[]` is each of a list, `{}` each key of a table (last only).
local function at(obj, path, visit)
    local parts = {}
    for p in path:gmatch('[^.]+') do parts[#parts + 1] = p end
    local function walk(o, i)
        if type(o) ~= 'table' then return end
        local p, last = parts[i], i == #parts
        local key = p:match('^(.-)%[%]$')
        local mapKey = p:match('^(.-){}$')
        if key then
            local list = o[key]
            if type(list) ~= 'table' then return end
            for _, x in ipairs(list) do
                if last then visit(x) else walk(x, i + 1) end
            end
        elseif mapKey then
            local map = o[mapKey]
            if type(map) ~= 'table' then return end
            for k in pairs(map) do visit(k) end
        elseif last then
            visit(o[p])
        else
            walk(o[p], i + 1)
        end
    end
    walk(obj, 1)
end

--- Every reference in one document, each as fn({ kind = 'world' | 'var' | 'card', id, plus where it is found:
--- node + field, thing + step + field, thing + named, or settings }).
function DirectorRefs.each(doc, fn)
    local function emit(kind, id, where)
        if type(id) ~= 'string' or id == '' then return end
        local r = { kind = kind, id = id }
        for k, v in pairs(where) do r[k] = v end
        fn(r)
    end
    local function field(f, holder, where)
        local v = holder[f.key]
        if type(v) == 'table' and type(v.var) == 'string' then emit('var', v.var, where) end
        local d = DirectorFields.get(f.kind)
        if not d then return end
        if d.names == 'worlds' then
            -- A group ('group:<name>') expands to its members of the field's kind.
            local list = type(v) == 'table' and v or {}
            if f.groups then list = DirectorNodes.expandThings(doc.world, v, f.worldKind) end
            for _, x in ipairs(list) do emit('world', x, where) end
        elseif d.names then
            emit(d.names, v, where)
        end
        if d.refs and type(v) == 'table' then
            for kind, keys in pairs(d.refs) do
                for _, k in ipairs(keys) do emit(kind, v[k], where) end
            end
        end
        local sib = d.sibling
        if sib and (v == nil and f.default or v) == sib.when then emit(sib.names, holder[sib.key], where) end
    end
    for _, n in ipairs(type(doc.nodes) == 'table' and doc.nodes or {}) do
        local def = type(n) == 'table' and DirectorNodes.get(n.type)
        if def and type(n.props) == 'table' then
            for _, f in ipairs(def.props) do field(f, n.props, { node = n, field = f }) end
        end
    end
    for _, w in ipairs(type(doc.world) == 'table' and doc.world or {}) do
        local def = type(w) == 'table' and type(w.def) == 'table' and w.def or nil
        local t = def and type(def.tasks) == 'table' and def.tasks or nil
        for _, s in ipairs(t and type(t.list) == 'table' and t.list or {}) do
            local d = type(s) == 'table' and DirectorTasks.get(s.t)
            for _, f in ipairs(d and d.fields or {}) do field(f, s, { thing = w, step = s, stepDef = d, field = f }) end
        end
        for _, p in ipairs(DirectorThings.NAMED_IN) do
            if def and p.kind == w.kind then at(def, p.path, function(id) emit('world', id, { thing = w, named = p }) end) end
        end
    end
    local st = type(doc.settings) == 'table' and doc.settings or nil
    for _, p in ipairs(st and DirectorThings.SETTINGS_NAMED or {}) do
        at(st, p.path, function(id) emit('world', id, { settings = p }) end)
    end
end

--- The text for a reference in a "who names this" list (same as namerText in refs.js).
function DirectorRefs.namerText(r)
    if r.node then
        local def = DirectorNodes.get(r.node.type)
        return tostring(def and def.title or r.node.type)
    end
    local name = r.thing and tostring(r.thing.label or r.thing.id) or ''
    if r.step then return ('%s\'s task: %s'):format(name, tostring(r.stepDef and r.stepDef.label or r.step.t)) end
    if r.named then return ('%s: %s'):format(name, r.named.says) end
    return r.settings and r.settings.says or '?'
end
