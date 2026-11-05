--[[
    RepairHelper.lua
    Standalone extraction of BigFoot's RepairHelper module.
    Automatically repairs all equipment when visiting a merchant.

    Original: BigFoot RepairHelper (obfuscated)
    Extraction: clean rewrite, no BigFoot dependency

    ------------------------------------------------------------------
    Port target: World of Warcraft: Forever ("wowf", client 1.60.1,
    TOC Interface 16001, modern Mainline API ~12.1.5, Lua 5.1).

    Port notes
    ----------
    * The globals removed on the Forever client (GetSpellInfo,
      GetItemInfo, GetContainerItemInfo, GetContainerNumSlots,
      GetContainerNumFreeSlots, UnitAura*, GetSpellCooldown,
      GetSpellTexture, ...) are NOT used by this addon, so no C_Spell /
      C_Item / C_Container / C_UnitAuras rewrite was required.
    * The merchant/repair API used here (CanMerchantRepair,
      GetRepairAllCost, RepairAllItems) still exists on modern Mainline;
      RepairAllItems is documented for both the 12.1.5 "standard" game
      type and the 1.60.1 "forever" game type.
    * Guild-bank helpers (CanGuildBankRepair, GetGuildBankMoney,
      GetGuildBankWithdrawMoney) are probed at runtime and degrade
      gracefully to personal funds instead of erroring out.
    * MERCHANT_SHOW / MERCHANT_UPDATE / MERCHANT_CLOSED all still exist
      on modern clients. MERCHANT_UPDATE is registered as a fallback in
      case a custom merchant UI only fires updates; a per-merchant flag
      keeps it from repairing twice.
    * No combat-log events are registered and no player health, power or
      name values are read, so both the disabled combat log and the
      "secret values" restrictions on the Forever client are irrelevant
      to this addon.
]]

local ADDON_NAME = "RepairHelper"
local PREFIX = "|cff00ff00" .. ADDON_NAME .. "|r: "

--------------------------------------------------------------------
-- Modern-client helpers
--------------------------------------------------------------------

-- Some clients keep strtrim, some do not. Never fail on a missing global.
local strtrim = strtrim or function(s)
    return (s or ""):gsub("^%s*(.-)%s*$", "%1")
end

-- Chat output: DEFAULT_CHAT_FRAME is the modern, reload-safe entry point.
-- ChatFrame1 is kept only as a last-resort fallback.
local function Print(msg)
    if not msg or msg == "" then return end
    local frame = DEFAULT_CHAT_FRAME or ChatFrame1
    if frame and frame.AddMessage then
        frame:AddMessage(msg, 1.0, 1.0, 0.0)
    elseif print then
        print(msg)
    end
end

-- Runtime API probe: a global that was removed simply returns false
-- instead of throwing "attempt to call a nil value" at the call site.
local function HasAPI(name)
    return type(_G[name]) == "function"
end

--------------------------------------------------------------------
-- Localization
--------------------------------------------------------------------
local L = {}
local locale = GetLocale()
if locale == "zhCN" then
    L.FORMAT_GOLD   = "你在修理上面花费了%d金币%d银币%d铜币%s。"
    L.FORMAT_SILVER = "你在修理上面花费了%d银币%d铜币%s。"
    L.FORMAT_COPPER = "你在修理上面花费了%d铜币%s。"
    L.GUILD_MONEY   = "(公会资金)"
    L.ENABLED       = "修理助手已启用"
    L.DISABLED      = "修理助手已禁用"
    L.GUILD_ON      = "优先使用公会资金修理：开启"
    L.GUILD_OFF     = "优先使用公会资金修理：关闭"
    L.SELF_ON       = "公会资金不足时使用个人资金修理：开启"
    L.SELF_OFF      = "公会资金不足时使用个人资金修理：关闭"
    L.USAGE         = "用法: /rh <enable|disable|guild|self>"
    L.UNSUPPORTED   = "当前客户端缺少修理相关 API，无法自动修理。"
elseif locale == "zhTW" then
    L.FORMAT_GOLD   = "你在修理上面花費了%d金幣%d銀幣%d銅幣%s。"
    L.FORMAT_SILVER = "你在修理上面花費了%d銀幣%d銅幣%s。"
    L.FORMAT_COPPER = "你在修理上面花費了%d銅幣%s。"
    L.GUILD_MONEY   = "(公會資金)"
    L.ENABLED       = "修理助手已啟用"
    L.DISABLED      = "修理助手已禁用"
    L.GUILD_ON      = "優先使用公會資金修理：開啟"
    L.GUILD_OFF     = "優先使用公會資金修理：關閉"
    L.SELF_ON       = "公會資金不足時使用個人資金修理：開啟"
    L.SELF_OFF      = "公會資金不足時使用個人資金修理：關閉"
    L.USAGE         = "用法: /rh <enable|disable|guild|self>"
    L.UNSUPPORTED   = "目前客戶端缺少修理相關 API，無法自動修理。"
else
    L.FORMAT_GOLD   = "You have spent %d gold %d silver %d copper on repairs.%s"
    L.FORMAT_SILVER = "You have spent %d silver %d copper on repairs.%s"
    L.FORMAT_COPPER = "You have spent %d copper on repairs.%s"
    L.GUILD_MONEY   = "(Guild Money)"
    L.ENABLED       = "RepairHelper enabled"
    L.DISABLED      = "RepairHelper disabled"
    L.GUILD_ON      = "Prefer guild bank for repairs: ON"
    L.GUILD_OFF     = "Prefer guild bank for repairs: OFF"
    L.SELF_ON       = "Use personal funds when guild bank insufficient: ON"
    L.SELF_OFF      = "Use personal funds when guild bank insufficient: OFF"
    L.USAGE         = "Usage: /rh <enable|disable|guild|self>"
    L.UNSUPPORTED   = "This client is missing the repair API; auto-repair unavailable."
end

--------------------------------------------------------------------
-- Saved Variables  (RepairHelperSV)
-- {
--     enabled  = true,   -- auto-repair on/off
--     useGuild = false,  -- prefer guild bank money
--     useSelf  = false,  -- fallback to personal money when guild insufficient
-- }
--------------------------------------------------------------------
local function InitSV()
    if not RepairHelperSV then
        RepairHelperSV = {}
    end
    if RepairHelperSV.enabled == nil then
        RepairHelperSV.enabled = true
    end
    if RepairHelperSV.useGuild == nil then
        RepairHelperSV.useGuild = false
    end
    if RepairHelperSV.useSelf == nil then
        RepairHelperSV.useSelf = false
    end
end

--------------------------------------------------------------------
-- Money formatting
--------------------------------------------------------------------
local function FormatMoney(amount, isGuild)
    amount = tonumber(amount)
    if not amount then return nil end

    local gold   = math.floor(amount / 10000)
    local rest   = amount - gold * 10000
    local silver = math.floor(rest / 100)
    local copper = rest - silver * 100

    local suffix = ""
    if isGuild then
        suffix = L.GUILD_MONEY
    end

    local msg
    if gold > 0 then
        msg = string.format(L.FORMAT_GOLD, gold, silver, copper, suffix)
    elseif silver > 0 then
        msg = string.format(L.FORMAT_SILVER, silver, copper, suffix)
    elseif copper > 0 then
        msg = string.format(L.FORMAT_COPPER, copper, suffix)
    end
    return msg
end

--------------------------------------------------------------------
-- Guild bank probes
--   CanGuildBankRepair / GetGuildBankMoney / GetGuildBankWithdrawMoney
--   are still present on modern Mainline, but the Forever client is a
--   third-party build, so every one of them is guarded.
--------------------------------------------------------------------
local function GuildBankRepairAvailable()
    if not HasAPI("CanGuildBankRepair") then return false end
    local ok, canRepair = pcall(CanGuildBankRepair)
    return ok and canRepair and true or false
end

local function GuildBankCovers(cost)
    if not HasAPI("GetGuildBankWithdrawMoney") or not HasAPI("GetGuildBankMoney") then
        return false
    end
    local okW, withdraw   = pcall(GetGuildBankWithdrawMoney)
    local okB, bankMoney  = pcall(GetGuildBankMoney)
    if not okW or not okB then return false end

    withdraw  = tonumber(withdraw)
    bankMoney = tonumber(bankMoney)
    if not withdraw or not bankMoney then return false end

    -- -1 means "no withdraw limit set" on old and modern clients alike.
    if withdraw == -1 then
        withdraw = bankMoney
    else
        withdraw = math.min(withdraw, bankMoney)
    end
    return withdraw >= cost
end

--------------------------------------------------------------------
-- Event frame
--------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

-- Per-merchant guard so MERCHANT_UPDATE (the fallback) cannot repair
-- and report twice for the same merchant visit.
local merchantHandled = false

local MERCHANT_EVENTS = { "MERCHANT_SHOW", "MERCHANT_UPDATE", "MERCHANT_CLOSED" }

-- RegisterEvent raises on an unknown event name; a pcall keeps the
-- addon loading even if a third-party client dropped one of them.
local function SafeRegister(event)
    if not event then return false end
    return pcall(eventFrame.RegisterEvent, eventFrame, event)
end

local function SafeUnregister(event)
    if not event then return false end
    return pcall(eventFrame.UnregisterEvent, eventFrame, event)
end

local function RegisterMerchantEvents()
    for i = 1, #MERCHANT_EVENTS do
        SafeRegister(MERCHANT_EVENTS[i])
    end
end

local function UnregisterMerchantEvents()
    for i = 1, #MERCHANT_EVENTS do
        SafeUnregister(MERCHANT_EVENTS[i])
    end
end

local function TryRepair()
    -- GetRepairAllCost / RepairAllItems are the only hard requirements.
    if not HasAPI("GetRepairAllCost") or not HasAPI("RepairAllItems") then
        return nil, true -- signal "API missing", not an error
    end

    -- CanMerchantRepair is optional: if it is gone, let the cost query
    -- below decide instead of blocking repairs outright.
    if HasAPI("CanMerchantRepair") then
        local ok, canRepair = pcall(CanMerchantRepair)
        if not ok or not canRepair then return 0, false end
    end

    local okCost, cost, canRepair = pcall(GetRepairAllCost)
    if not okCost then return 0, false end

    cost = tonumber(cost)
    if not cost or cost <= 0 then return 0, false end
    if canRepair == false then return 0, false end

    local useGuildMoney = false
    local repaired = false

    local function RepairWithPersonalFunds()
        return pcall(RepairAllItems, false)
    end

    if RepairHelperSV.useGuild and GuildBankRepairAvailable() then
        if GuildBankCovers(cost) then
            -- Guild bank has enough money: repair on the guild's tab.
            if pcall(RepairAllItems, true) then
                useGuildMoney = true
                repaired = true
            elseif RepairHelperSV.useSelf then
                repaired = RepairWithPersonalFunds()
            end
        elseif RepairHelperSV.useSelf then
            -- Guild bank cannot cover the bill and the user allowed the
            -- personal-funds fallback.
            repaired = RepairWithPersonalFunds()
        end
        -- else: guild preferred, guild short, no fallback -> original
        -- behaviour is to leave the equipment unrepaired.
    else
        -- Guild bank not available (no guild / no permission / function
        -- removed on this client) -> repair with personal funds, which
        -- is the original fallback behaviour and keeps the addon useful.
        repaired = RepairWithPersonalFunds()
    end

    -- Only report a cost when a repair call actually went through.
    return repaired and cost or 0, false, useGuildMoney
end

local function OnMerchantEvent(event)
    if event == "MERCHANT_CLOSED" then
        merchantHandled = false
        return
    end

    if event == "MERCHANT_SHOW" then
        merchantHandled = false
    end

    if merchantHandled then return end

    local cost, unsupported, useGuildMoney = TryRepair()

    if unsupported then
        -- Core repair API is gone entirely: tell the player once per
        -- merchant visit and stay idle instead of spamming updates.
        merchantHandled = true
        Print(PREFIX .. L.UNSUPPORTED)
        return
    end

    if not cost or cost <= 0 then
        -- Nothing to repair yet -- or the merchant's price data is not
        -- ready on the first MERCHANT_UPDATE. Do NOT lock the guard, so
        -- a later MERCHANT_UPDATE can retry. Nothing is printed here, so
        -- repeated retries stay silent.
        return
    end

    -- Repaired (or a repair call was attempted): lock this visit so the
    -- fallback event cannot repair or report twice.
    merchantHandled = true
    local msg = FormatMoney(cost, useGuildMoney)
    if msg then Print(msg) end
end

eventFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        SafeUnregister("PLAYER_LOGIN")
        InitSV()
        if RepairHelperSV.enabled then
            RegisterMerchantEvents()
        end
    elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" or event == "MERCHANT_CLOSED" then
        OnMerchantEvent(event)
    end
end)

-- Modern clients may already be past PLAYER_LOGIN when an addon file is
-- loaded (delayed load / reload with the UI up). IsLoggedIn() covers it
-- so the addon never sits idle waiting for an event that already fired.
if type(IsLoggedIn) == "function" and IsLoggedIn() then
    InitSV()
    if RepairHelperSV.enabled then
        RegisterMerchantEvents()
    end
else
    eventFrame:RegisterEvent("PLAYER_LOGIN")
end

--------------------------------------------------------------------
-- Toggle API  (kept for compatibility / slash command use)
--------------------------------------------------------------------
function RepairHelper_ToggleEnable(enable)
    InitSV()
    if enable == 1 or enable == true then
        RepairHelperSV.enabled = true
        RegisterMerchantEvents()
    else
        RepairHelperSV.enabled = false
        UnregisterMerchantEvents()
    end
end

function RepairHelper_ToggleUseGuild(enable)
    InitSV()
    RepairHelperSV.useGuild = (enable == 1 or enable == true)
end

function RepairHelper_ToggleUseSelfMoneyAuto(enable)
    InitSV()
    RepairHelperSV.useSelf = (enable == 1 or enable == true)
end

--------------------------------------------------------------------
-- Slash command:  /rh  or  /repairhelper
--------------------------------------------------------------------
SLASH_REPAIRHELPER1 = "/rh"
SLASH_REPAIRHELPER2 = "/repairhelper"
SlashCmdList["REPAIRHELPER"] = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "enable" or msg == "on" then
        RepairHelper_ToggleEnable(1)
        Print(PREFIX .. L.ENABLED)
    elseif msg == "disable" or msg == "off" then
        RepairHelper_ToggleEnable(nil)
        Print(PREFIX .. L.DISABLED)
    elseif msg == "guild" then
        InitSV()
        RepairHelperSV.useGuild = not RepairHelperSV.useGuild
        local state = RepairHelperSV.useGuild and L.GUILD_ON or L.GUILD_OFF
        Print(PREFIX .. state)
    elseif msg == "self" then
        InitSV()
        RepairHelperSV.useSelf = not RepairHelperSV.useSelf
        local state = RepairHelperSV.useSelf and L.SELF_ON or L.SELF_OFF
        Print(PREFIX .. state)
    else
        Print(PREFIX .. L.USAGE)
    end
end
