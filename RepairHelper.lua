--[[
    RepairHelper.lua
    Standalone extraction of BigFoot's RepairHelper module.
    Automatically repairs all equipment when visiting a merchant.

    Original: BigFoot RepairHelper (obfuscated)
    Extraction: clean rewrite, no BigFoot dependency
]]

local ADDON_NAME = "RepairHelper"

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
-- Event frame
--------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")

local function OnMerchantShow()
    if not CanMerchantRepair() then return end

    local cost, canRepair = GetRepairAllCost()
    if not canRepair or cost <= 0 then return end

    local useGuildMoney = false
    local repaired = false

    if RepairHelperSV.useGuild and CanGuildBankRepair and CanGuildBankRepair() then
        local withdraw = GetGuildBankWithdrawMoney()
        local bankMoney = GetGuildBankMoney()
        if withdraw == -1 then
            withdraw = bankMoney
        else
            withdraw = min(withdraw, bankMoney)
        end

        if withdraw >= cost then
            RepairAllItems(1)
            useGuildMoney = true
            repaired = true
        elseif RepairHelperSV.useSelf then
            RepairAllItems()
            repaired = true
        end
    else
        RepairAllItems()
        repaired = true
    end

    if repaired then
        local msg = FormatMoney(cost, useGuildMoney)
        if msg then
            ChatFrame1:AddMessage(msg, 1.0, 1.0, 0.0)
        end
    end
end

eventFrame:SetScript("OnEvent", function(self, event, ...)
    if event == "MERCHANT_SHOW" then
        OnMerchantShow()
    elseif event == "PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        InitSV()
        if RepairHelperSV.enabled then
            self:RegisterEvent("MERCHANT_SHOW")
        end
    end
end)
eventFrame:RegisterEvent("PLAYER_LOGIN")

--------------------------------------------------------------------
-- Toggle API  (kept for compatibility / slash command use)
--------------------------------------------------------------------
function RepairHelper_ToggleEnable(enable)
    InitSV()
    if enable == 1 or enable == true then
        RepairHelperSV.enabled = true
        eventFrame:RegisterEvent("MERCHANT_SHOW")
    else
        RepairHelperSV.enabled = false
        eventFrame:UnregisterEvent("MERCHANT_SHOW")
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
    msg = strtrim(msg:lower())
    if msg == "enable" or msg == "on" then
        RepairHelper_ToggleEnable(1)
        ChatFrame1:AddMessage("|cff00ff00RepairHelper|r: " .. L.ENABLED, 1, 1, 0)
    elseif msg == "disable" or msg == "off" then
        RepairHelper_ToggleEnable(nil)
        ChatFrame1:AddMessage("|cff00ff00RepairHelper|r: " .. L.DISABLED, 1, 1, 0)
    elseif msg == "guild" then
        InitSV()
        RepairHelperSV.useGuild = not RepairHelperSV.useGuild
        local state = RepairHelperSV.useGuild and L.GUILD_ON or L.GUILD_OFF
        ChatFrame1:AddMessage("|cff00ff00RepairHelper|r: " .. state, 1, 1, 0)
    elseif msg == "self" then
        InitSV()
        RepairHelperSV.useSelf = not RepairHelperSV.useSelf
        local state = RepairHelperSV.useSelf and L.SELF_ON or L.SELF_OFF
        ChatFrame1:AddMessage("|cff00ff00RepairHelper|r: " .. state, 1, 1, 0)
    else
        ChatFrame1:AddMessage("|cff00ff00RepairHelper|r: " .. L.USAGE, 1, 1, 0)
    end
end
