-- ============================================
-- WHO IS CALLING — shared/invoker.lua (spur_core's first file, on both sides)
-- ============================================
--
-- spur_core asks GetInvokingResource() which resource is calling it, and files what that resource registers under its
-- name: secure events and callbacks, registries, panels, vehicles (some 50 places). While spur_core's own files load,
-- nothing is calling it. But when another resource started it (StartResource: whip_devlink's restart, a resource's
-- restart button), Cfx.re names that resource as the caller until the load ends. On 31 Oct spur_core then refused 403
-- of its own events as whip_devlink's ("names starting spur_core: belong to spur_core") and came up half working.
--
-- So while spur_core is still starting there is no caller, and every one of those places reads spur_core.

local SELF = GetCurrentResourceName()
local nativeInvoker = GetInvokingResource
local started = false

function GetInvokingResource()
    if not started then
        if GetResourceState(SELF) == 'starting' then return nil end
        started = true
    end
    return nativeInvoker()
end

-- ============================================
-- WHAT spur_core EXPORTS — for HasExport (lib/satellite.lua's Whip.has)
-- ============================================
--
-- Every name given to exports() on this side is noted as it is made, so a resource can ask whether this spur_core
-- has a call before it uses one newer than the oldest whip it supports. The global works as Cfx.re's still:
-- exports(name, fn) makes an export, exports.other:Call() reaches another resource.
local nativeExports = exports
local exported = {}
-- And where each one's function is, as Cfx.re names a call to it ('ref call [file[first..last]]'): /whipcost counts
-- the calls spur_core is asked by that name (tools/whipcost.lua), and shows the export's.
WhipExportsAt = {}
exports = setmetatable({}, {
    __call = function(_, name, fn)
        exported[name] = true
        if type(fn) == 'function' then
            local di = debug.getinfo(fn, 'S')
            WhipExportsAt[('%s[%d..%d]'):format(di.short_src, di.linedefined, di.lastlinedefined)] = name
        end
        return nativeExports(name, fn)
    end,
    __index = function(_, k) return nativeExports[k] end,
})

--- Has spur_core this export, on this side?
exports('HasExport', function(name)
    return type(name) == 'string' and exported[name] == true
end)
