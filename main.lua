local mod = RegisterMod("The Purgatory Package", 1)
local game = Game()
local itemConfig = Isaac.GetItemConfig()

local DEVILS_COIN_ID = nil
local OLYMO_FAMILIAR_ID = nil
local CONFIG_OLYMO = nil
local FAMILIAR_VARIANT = nil
local RNG_SHIFT_INDEX = 35

-- Configurações do familiar Olymo
local OLYMO_SHOOTING_TICK_COOLDOWN = 45
local OLYMO_TEAR_SPEED = 5
local OLYMO_TEAR_SCALE = 1.0
local OLYMO_TEAR_DAMAGE = 3.5

-- Cálculo de chance baseado em sorte negativa
function mod:CalculateSuccessChance(player)
    local luck = player.Luck
    local baseFailChance = 66
    
    -- Sorte negativa REDUZ a chance de falha
    if luck < 0 then
        baseFailChance = baseFailChance + (luck * 5)
    end
    
    -- Mínimo de 10% de falha
    baseFailChance = math.max(10, baseFailChance)
    return 100 - baseFailChance
end

-- Sistema de familiar usando MC_EVALUATE_CACHE
function mod:EvaluateCache(player)
    if not OLYMO_FAMILIAR_ID or not CONFIG_OLYMO then
        return
    end
    
    local effects = player:GetEffects()
    local count = effects:GetCollectibleEffectNum(OLYMO_FAMILIAR_ID) + player:GetCollectibleNum(OLYMO_FAMILIAR_ID)
    local rng = RNG()
    local seed = math.max(Random(), 1)
    rng:SetSeed(seed, RNG_SHIFT_INDEX)

    player:CheckFamiliar(FAMILIAR_VARIANT, count, rng, CONFIG_OLYMO)
end

-- Inicialização do familiar
function mod:HandleInit(familiar)
    familiar:AddToFollowers()
    
    -- Configurações para familiar terrestre
    familiar.CollisionDamage = 0
    familiar.GridCollisionClass = GridCollisionClass.COLLISION_SOLID
    
    -- Configurar sprite
    local sprite = familiar:GetSprite()
    sprite:Load("gfx/familiar_olymo.anm2", true)
    sprite:Play("Idle", true)
    
    Isaac.DebugString("[Olymo] Familiar inicializado!")
end

-- Atualização do familiar
function mod:HandleUpdate(familiar)
    local sprite = familiar:GetSprite()
    local player = familiar.Player

    -- Verifica se o jogador está atirando
    local fireDirection = player:GetFireDirection()
    local playerShooting = fireDirection ~= Direction.NO_DIRECTION

    -- Só atira quando o jogador está atirando e o cooldown acabou
    if playerShooting and familiar.FireCooldown == 0 then
        -- Atirar em 4 direções
        local directions = {
            Vector(1, 0),   -- Direita
            Vector(-1, 0),  -- Esquerda
            Vector(0, -1),  -- Cima
            Vector(0, 1)    -- Baixo
        }
        
        -- Toca animação de tiro
        sprite:Play("ShootDown", true)
        
        for _, direction in ipairs(directions) do
            -- Criar lágrima de veneno
            local tear = Isaac.Spawn(
                EntityType.ENTITY_TEAR,
                TearVariant.BLUE,
                0,
                familiar.Position,
                direction * OLYMO_TEAR_SPEED,
                familiar
            ):ToTear()

            if tear then
                tear.Scale = OLYMO_TEAR_SCALE
                tear.CollisionDamage = OLYMO_TEAR_DAMAGE
                tear:SetColor(Color(0.2, 0.8, 0.2, 1, 0, 0, 0), 0, 0, false, false) -- Verde venenoso
                tear:AddTearFlags(TearFlags.TEAR_POISON)
                tear.FallingSpeed = 0
                tear.FallingAccel = 0
            end
        end
        
        familiar.FireCooldown = OLYMO_SHOOTING_TICK_COOLDOWN
    end

    -- Volta para animação de idle quando termina
    if sprite:IsFinished() then
        sprite:Play("Idle", true)
    end

    -- Seguir o jogador
    familiar:FollowParent()
    familiar.FireCooldown = math.max(familiar.FireCooldown - 1, 0)
end

-- Função para usar Devil's Coin
function mod:OnUseDevilsCoin(itemID, rng, player, useFlags, slot, customVarData)
    if not DEVILS_COIN_ID or itemID ~= DEVILS_COIN_ID then
        return
    end
    
    Isaac.DebugString("[Devil's Coin] Item usado!")
    
    local successChance = mod:CalculateSuccessChance(player)
    local roll = math.random(1, 100)
    local success = roll <= successChance
    
    Isaac.DebugString("[Devil's Coin] Luck: " .. player.Luck .. " | Success Chance: " .. successChance .. "% | Roll: " .. roll)
    
    -- Encontrar pickups na sala
    local entities = Isaac.GetRoomEntities()
    local pickups = {}
    
    for _, entity in ipairs(entities) do
        if entity.Type == EntityType.ENTITY_PICKUP then
            local pickup = entity:ToPickup()
            if pickup then
                table.insert(pickups, {
                    pos = pickup.Position,
                    type = pickup.Type,
                    variant = pickup.Variant,
                    subtype = pickup.SubType,
                    entity = pickup
                })
            end
        end
    end
    
    Isaac.DebugString("[Devil's Coin] Encontrados " .. #pickups .. " pickups")
    
    if success then
        Isaac.DebugString("[Devil's Coin] SUCESSO! Duplicando...")
        
        -- Duplica todos os pickups
        for _, data in ipairs(pickups) do
            Isaac.Spawn(data.type, data.variant, data.subtype, data.pos, Vector.Zero, nil)
        end
        
        game:ShakeScreen(10)
        SFXManager():Play(SoundEffect.SOUND_SATAN_GROW, 1.0, 0, false, 1.0)
        
    else
        Isaac.DebugString("[Devil's Coin] FALHA! Removendo...")
        
        -- Remove todos os pickups
        for _, data in ipairs(pickups) do
            data.entity:Remove()
        end
        
        game:ShakeScreen(10)
        SFXManager():Play(SoundEffect.SOUND_DEVIL_CARD, 1.0, 0, false, 1.0)
    end
    
    return {
        Discharge = true,
        Remove = false,
        ShowAnim = true
    }
end

-- Inicialização do mod
function mod:OnGameStart()
    DEVILS_COIN_ID = Isaac.GetItemIdByName("Devil's Coin")
    OLYMO_FAMILIAR_ID = Isaac.GetItemIdByName("Olymo's Contract")
    FAMILIAR_VARIANT = Isaac.GetEntityVariantByName("Olymo")
    
    if DEVILS_COIN_ID and DEVILS_COIN_ID > 0 then
        Isaac.DebugString("[Devil's Coin] ID encontrado: " .. DEVILS_COIN_ID)
        
        -- Integração EID
        if EID then
            EID:addCollectible(
                DEVILS_COIN_ID,
                "{{ColorGreen}}Success{{CR}}: Duplicates all pickups in the room {{Coin}} {{Key}} {{Bomb}} {{Chest}} {{Card}} {{Pill}} {{Trinket}} {{Collectible}}.#{{ColorRed}}Failure{{CR}}: Removes all pickups in the room.#{{Luck}} Luck: 66% base fail chance. Each point of negative Luck reduces fail chance by 5% (min 10%).#{{Battery}} 6 charges.",
                "Devil's Coin",
                "en_us"
            )
            EID:addCollectible(
                DEVILS_COIN_ID,
                "{{ColorGreen}}Sucesso{{CR}}: Duplica todos os pickups da sala {{Coin}} {{Key}} {{Bomb}} {{Chest}} {{Card}} {{Pill}} {{Trinket}} {{Collectible}}.#{{ColorRed}}Falha{{CR}}: Remove todos os pickups da sala.#{{Luck}} Sorte: 66% de falha base. Cada ponto de Sorte negativa reduz a chance de falha em 5% (mín 10%).#{{Battery}} 6 cargas.",
                "Moeda do Diabo",
                "pt_br"
            )
        end
    else
        Isaac.DebugString("[Devil's Coin] ERRO: Item não encontrado!")
    end
    
    if OLYMO_FAMILIAR_ID and OLYMO_FAMILIAR_ID > 0 and FAMILIAR_VARIANT and FAMILIAR_VARIANT > 0 then
        Isaac.DebugString("[Olymo] ID encontrado: " .. OLYMO_FAMILIAR_ID .. " | Variant: " .. FAMILIAR_VARIANT)
        
        CONFIG_OLYMO = itemConfig:GetCollectible(OLYMO_FAMILIAR_ID)
        
        if CONFIG_OLYMO then
            Isaac.DebugString("[Olymo] CONFIG_OLYMO carregado com sucesso!")
        else
            Isaac.DebugString("[Olymo] ERRO: CONFIG_OLYMO não foi carregado!")
        end
        
        -- Integração EID
        if EID then
            EID:addCollectible(
                OLYMO_FAMILIAR_ID,
                "{{Familiar}} Spawns Olymo, a familiar that follows you and shoots {{ColorGreen}}poison tears{{CR}} in 4 directions when you attack.#{{Poison}} Olymo shoots {{ColorGreen}}poison tears{{CR}} that deal 3.5 damage and apply poison.#{{Familiar}} Olymo stays on the ground and follows you at a distance.",
                "Olymo's Contract",
                "en_us"
            )
            EID:addCollectible(
                OLYMO_FAMILIAR_ID,
                "{{Familiar}} Invoca Olymo, um familiar que te segue e atira {{ColorGreen}}lágrimas de veneno{{CR}} em 4 direções quando você ataca.#{{Poison}} Olymo atira {{ColorGreen}}lágrimas de veneno{{CR}} que causam 3.5 de dano e aplicam veneno.#{{Familiar}} Olymo fica no chão e te segue a uma distância.",
                "Contrato de Olymo",
                "pt_br"
            )
        end
    else
        Isaac.DebugString("[Olymo] ERRO: Item ou variant não encontrado! OLYMO_FAMILIAR_ID = " .. tostring(OLYMO_FAMILIAR_ID) .. " FAMILIAR_VARIANT = " .. tostring(FAMILIAR_VARIANT))
    end
end

-- Callbacks
mod:AddCallback(ModCallbacks.MC_POST_GAME_STARTED, mod.OnGameStart)
mod:AddCallback(ModCallbacks.MC_USE_ITEM, mod.OnUseDevilsCoin)
mod:AddCallback(ModCallbacks.MC_EVALUATE_CACHE, mod.EvaluateCache, CacheFlag.CACHE_FAMILIARS)
mod:AddCallback(ModCallbacks.MC_FAMILIAR_INIT, mod.HandleInit, FAMILIAR_VARIANT)
mod:AddCallback(ModCallbacks.MC_FAMILIAR_UPDATE, mod.HandleUpdate, FAMILIAR_VARIANT)

Isaac.DebugString("[The Purgatory Package] Mod carregado!")
