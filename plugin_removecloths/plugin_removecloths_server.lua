local Settings = {
  item = 'trauma_shears',
  distance = 2.75,
  interval = 750,
  -- false = everyone with scissors; optionally use an ACE such as medical.shears.
  requiredAce = false
}
local pluginData = {
  name = 'removecloths', description = 'Serverprüfung für Kleiderscheren',
  author = 'Michael Pollenski', version = '2.0.1'
}
RegisterServerPlugin(pluginData, function(print)
  local pending, actors, targets, lastRequest = {}, {}, {}, {}
  local sequence = 0
  local function positiveInteger(value)
    return type(value) == 'number' and value > 0 and value < 2147483647 and value % 1 == 0
  end
  local function result(actor, request, ok, reason)
    TriggerClientEvent('medical_shears:result', actor, request, ok, reason)
  end
  local function valid(actor, target, removing)
    if not positiveInteger(target) or actor == target or not GetPlayerName(target) then
      return false, 'invalid_target'
    end
    if Settings.requiredAce and not IsPlayerAceAllowed(actor, Settings.requiredAce) then
      return false, 'denied'
    end
    if removing then
      if GetResourceState('ox_inventory') ~= 'started' then return false, 'inventory_offline' end
      local success, count = pcall(function()
        return exports.ox_inventory:Search(actor, 'count', Settings.item)
      end)
      if not success then return false, 'inventory_offline' end
      if type(count) ~= 'number' or count < 1 then return false, 'no_item' end
      local health = Player(target).state.healthBuffer
      if health and health.bodybag then return false, 'bodybag' end
    end
    if GetPlayerRoutingBucket(actor) ~= GetPlayerRoutingBucket(target) then
      return false, 'different_bucket'
    end
    local actorPed, targetPed = GetPlayerPed(actor), GetPlayerPed(target)
    if actorPed == 0 or targetPed == 0 or not DoesEntityExist(actorPed) or not DoesEntityExist(targetPed) then
      return false, 'invalid_target'
    end
    local a, b = GetEntityCoords(actorPed), GetEntityCoords(targetPed)
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    if dx * dx + dy * dy + dz * dz > Settings.distance * Settings.distance then
      return false, 'too_far'
    end
    return true
  end
  local function finish(operation, ok, reason)
    local p = pending[operation]
    if not p then return end
    pending[operation], actors[p.actor], targets[p.target] = nil, nil, nil
    if GetPlayerName(p.actor) then result(p.actor, p.request, ok, reason) end
  end
  RegisterNetEvent('medical_shears:request', function(request, target, part)
    local actor = source
    if not positiveInteger(request) then return end
    local now = GetGameTimer()
    if lastRequest[actor] and now - lastRequest[actor] < Settings.interval then
      result(actor, request, false, 'rate_limit')
      return
    end
    lastRequest[actor] = now
    local removing = part == 'upper' or part == 'lower'
    if not removing and part ~= 'restore_upper' and part ~= 'restore_lower' and part ~= 'restore_all' then
      result(actor, request, false, 'invalid_part')
      return
    end
    local ok, reason = valid(actor, target, removing)
    if not ok then result(actor, request, false, reason) return end
    if actors[actor] or targets[target] then result(actor, request, false, 'busy') return end
    sequence = sequence + 1
    local operation = sequence
    pending[operation] = { actor = actor, target = target, request = request }
    actors[actor], targets[target] = operation, operation
    TriggerClientEvent('medical_shears:apply', target, operation, part)
    SetTimeout(5000, function() finish(operation, false, 'timeout') end)
  end)
  RegisterNetEvent('medical_shears:applied', function(operation, ok, reason)
    if not positiveInteger(operation) then return end
    local p = pending[operation]
    if not p or source ~= p.target then return end
    -- The patient may only acknowledge their own outstanding operation.
    finish(operation, ok == true, type(reason) == 'string' and reason:sub(1, 80) or 'handler_error')
  end)
  AddEventHandler('playerDropped', function()
    local player = source
    lastRequest[player] = nil
    if actors[player] then finish(actors[player], false, 'invalid_target') end
    if targets[player] then finish(targets[player], false, 'invalid_target') end
  end)
  print('Kleiderschere: ox_inventory, Entfernung und Routing-Bucket werden serverseitig geprüft.')
end)
