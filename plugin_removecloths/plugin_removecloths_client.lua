local Settings = {
  item = 'trauma_shears', -- Same name in server file and ox_inventory.
  category = 'bandages',
  duration = 5000,
  restoreDuration = 2000,
  -- Standard-Freemode-Ersatzwerte, ohne dpClothing-Streamingdateien.
  presets = {
    male = { upper = { [11] = 15, [8] = 15, [3] = 15, [10] = 0, [9] = 0 }, lower = { [4] = 61 } },
    female = { upper = { [11] = 15, [8] = 15, [3] = 15, [10] = 0, [9] = 0 }, lower = { [4] = 14 } }
  }
}
local pluginData = {
  name = 'removecloths',
  description = 'Eigener Kleidungshandler für visn_are',
  author = 'Michael Pollenski',
  version = '2.0.1'
}
RegisterClientPlugin(pluginData, function(print)
  local pending, sequence = {}, 0
  -- Only components changed by this plugin are stored. Never overwrite an
  -- original snapshot when removing the same group a second time.
  local saved, savedPed, savedModel = {}, nil, nil
  local function currentSnapshot()
    local ped = PlayerPedId()
    if next(saved) and (savedPed ~= ped or savedModel ~= GetEntityModel(ped)) then
      -- Never put an old character's clothing onto a different ped/model.
      saved, savedPed, savedModel = {}, nil, nil
    end
    return ped
  end
  local function restoreClothing(group)
    local ped = currentSnapshot()
    local found = false
    for _, name in ipairs({ 'upper', 'lower' }) do
      if (group == 'all' or group == name) and saved[name] then
        local snapshot = saved[name]
        for component, value in pairs(snapshot) do
          SetPedComponentVariation(ped, component, value.drawable, value.texture, value.palette)
        end
        saved[name] = nil
        found = true
      end
    end
    if not next(saved) then savedPed, savedModel = nil, nil end
    return found, found and nil or 'nothing_saved'
  end
  local function removeClothing(group)
    if group ~= 'upper' and group ~= 'lower' then return false, 'invalid_part' end
    local ped = currentSnapshot()
    if saved[group] then return false, 'already_removed' end
    local model = GetEntityModel(ped)
    local preset
    if model == GetHashKey('mp_m_freemode_01') then preset = Settings.presets.male end
    if model == GetHashKey('mp_f_freemode_01') then preset = Settings.presets.female end
    if not preset then return false, 'unsupported_model' end
    local snapshot, changed = {}, false
    for component, drawable in pairs(preset[group]) do
      if not IsPedComponentVariationValid(ped, component, drawable, 0) then return false, 'invalid_preset' end
      snapshot[component] = {
        drawable = GetPedDrawableVariation(ped, component),
        texture = GetPedTextureVariation(ped, component),
        palette = GetPedPaletteVariation(ped, component)
      }
      if snapshot[component].drawable ~= drawable or snapshot[component].texture ~= 0 then changed = true end
    end
    if not changed then return false, 'already_removed' end
    saved[group], savedPed, savedModel = snapshot, ped, model
    for component, drawable in pairs(preset[group]) do
      SetPedComponentVariation(ped, component, drawable, 0, 0)
    end
    return true
  end
  -- The bodybag flag is set AFTER model loading in the supplied c_events.lua.
  -- Observe the actual result, not an unvalidated bodybag request.
  CreateThread(function()
    while true do
      if next(saved) then
        currentSnapshot()
        if ClientHealthBuffer and ClientHealthBuffer.bodybag then restoreClothing('all') end
      end
      Wait(100)
    end
  end)
  AddEventHandler('onResourceStop', function(resource)
    if resource == GetCurrentResourceName() then restoreClothing('all') end
  end)
  -- Local integration event: treatment ended by another medical script.
  AddEventHandler('visn_clothing:treatmentEnded', function() restoreClothing('all') end)
  AddEventHandler('visn_are:resetHealthBuffer', function() restoreClothing('all') end)
  if ENUM_HOOKABLE_EVENTS and ENUM_HOOKABLE_EVENTS.PLAYER_RESPAWNED then
    HookEventHandler(ENUM_HOOKABLE_EVENTS.PLAYER_RESPAWNED, function() restoreClothing('all') end)
  end
  local messages = {
    no_item = 'Du brauchst eine Kleiderschere.',
    invalid_target = 'Der Patient ist nicht verfügbar.',
    too_far = 'Der Patient ist zu weit entfernt.',
    different_bucket = 'Der Patient ist in einer anderen Instanz.',
    invalid_part = 'Ungültiger Kleidungsbereich.',
    inventory_offline = 'ox_inventory ist nicht verfügbar.',
    handler_error = 'Kleidungshandler fehlgeschlagen. F8-Konsole prüfen.',
    nothing_saved = 'Für diesen Bereich ist keine ausgezogene Kleidung gespeichert.',
    unsupported_model = 'Dieses Spielermodell wird nicht unterstützt.',
    invalid_preset = 'Die eingestellten Kleidungsnummern passen nicht zum Modell.',
    already_removed = 'Dieser Kleidungsbereich ist bereits entfernt.',
    bodybag = 'Der Patient befindet sich in einem Leichensack.',
    busy = 'Es läuft bereits eine Kleidungsaktion.',
    rate_limit = 'Bitte kurz warten.',
    timeout = 'Keine rechtzeitige Rückmeldung vom Patienten.',
    denied = 'Du darfst diese Aktion nicht verwenden.'
  }
  local function hasShears()
    if GetResourceState('ox_inventory') ~= 'started' then return false end
    local ok, count = pcall(function()
      return exports.ox_inventory:Search('count', Settings.item)
    end)
    return ok and type(count) == 'number' and count > 0
  end
  local function complete(id, ok, reason)
    local cb = pending[id]
    if not cb then return end
    pending[id] = nil
    ShowNotification(ok and 'Kleidung geändert.' or (messages[reason] or 'Kleidung konnte nicht entfernt werden.'))
    cb(ok == true)
  end
  RegisterNetEvent('medical_shears:result', function(id, ok, reason)
    if source ~= 65535 then return end
    complete(id, ok, reason)
  end)
  RegisterNetEvent('medical_shears:apply', function(operation, part)
    if source ~= 65535 then return end
    if type(operation) ~= 'number' then return end
    local ok, reason = false, 'handler_error'
    local restoring = part == 'restore_upper' or part == 'restore_lower' or part == 'restore_all'
    if not restoring and ClientHealthBuffer and ClientHealthBuffer.bodybag then
      reason = 'bodybag'
    else
      local invoked, result, errorCode = pcall(function()
        if restoring then return restoreClothing(part:sub(9)) end
        return removeClothing(part)
      end)
      if invoked then ok, reason = result == true, errorCode
      else print('Kleidungshandler: ' .. tostring(result)) end
    end
    TriggerServerEvent('medical_shears:applied', operation, ok, reason)
  end)
  local function run(part, clientData, callback)
    if (part == 'upper' or part == 'lower') and not hasShears() then
      ShowNotification(messages.no_item)
      callback(false)
      return
    end
    if next(pending) then
      ShowNotification(messages.busy)
      callback(false)
      return
    end
    -- In the supplied actions.lua clientData.source is the patient's server ID.
    local target = tonumber(clientData.source)
    if not target or target == GetPlayerServerId(PlayerId()) then
      ShowNotification(messages.invalid_target)
      callback(false)
      return
    end
    sequence = sequence + 1
    local id = sequence
    pending[id] = callback
    TriggerServerEvent('medical_shears:request', id, target, part)
    SetTimeout(8000, function() complete(id, false, 'timeout') end)
  end
  local function registerActions()
    local list = AVAILABLE_ACTIONS and AVAILABLE_ACTIONS[Settings.category]
    if type(list) ~= 'table' then return false end
    local definitions = {
      { name = 'CUT_CLOTHING_UPPER', part = 'upper', body = { 'TORSO', 'LEFT_ARM', 'RIGHT_ARM' }, label = 'Oberbekleidung' },
      { name = 'CUT_CLOTHING_LOWER', part = 'lower', body = { 'LEFT_LEG', 'RIGHT_LEG' }, label = 'Hose' },
      { name = 'RESTORE_CLOTHING_UPPER', part = 'restore_upper', body = { 'TORSO', 'LEFT_ARM', 'RIGHT_ARM' }, label = 'Oberbekleidung', restore = true },
      { name = 'RESTORE_CLOTHING_LOWER', part = 'restore_lower', body = { 'LEFT_LEG', 'RIGHT_LEG' }, label = 'Hose', restore = true },
      { name = 'RESTORE_CLOTHING_ALL', part = 'restore_all', label = 'Gesamte Kleidung', restore = true }
    }
    for _, definition in ipairs(definitions) do
      local exists = false
      for _, entry in pairs(list) do
        if entry.name == definition.name then exists = true break end
      end
      if not exists then
        local d = definition
        table.insert(list, {
          name = d.name,
          exclusiveBodyParts = d.body,
          hideOnSelf = true,
          cooldown = d.restore and Settings.restoreDuration or Settings.duration,
          animation = { lib = 'amb@medic@standing@tendtodead@idle_a', name = 'idle_a' },
          -- Intentionally no requiredItem: visn_are's generic item handling may
          -- consume items. Both client and server check ox_inventory directly.
          condition = function(healthBuffer)
            if d.restore then return true end
            return not (healthBuffer and healthBuffer.bodybag) and hasShears()
          end,
          action = function(clientData, healthBuffer, bodyPart, callback)
            if not d.restore and healthBuffer and healthBuffer.bodybag then
              ShowNotification(messages.bodybag)
              callback(false)
              return
            end
            run(d.part, clientData, callback)
          end,
          log = function(bodyPart, result)
            return result and (d.label .. (d.restore and ' angezogen.' or ' aufgeschnitten.')) or (d.label .. ': Aktion fehlgeschlagen.')
          end
        })
      end
    end
    print('Scherenaktionen unter ' .. Settings.category .. ' registriert.')
    return true
  end
  -- Handles plugin/entity initialization order without overwriting actions.lua.
  CreateThread(function()
    for _ = 1, 120 do
      if registerActions() then return end
      Wait(250)
    end
    print('FEHLER: AVAILABLE_ACTIONS.' .. Settings.category .. ' wurde nicht gefunden.')
  end)
end)
