--[[
    配置服务
    从后端拉取配置信息
--]]

local Service = require("services.service");
-- 游戏是否进入增购阶段
local matchIncreasePurchase = {};

-- 报名费保存信息
local enterFree = {};
---@class ConfigService
local ConfigService = class("ConfigService", Service);

function ConfigService:ctor()
    ConfigService.super.ctor(self, "SERVICE_TYPE_CONFIG", "ConfigProto");
end

--[[
    存储增购配置级别p
    self.purchaseLeave： 最小的不开启买入，过了最小的开启买入后就不能报名了 
--]]
function ConfigService:setIncreasePurchase(param)
    self.purchaseLeave = 100;
    for i, v in pairs(param) do
        if  v.purchase == 0 then 
            if self.purchaseLeave == nil or v.id < self.purchaseLeave then
                self.purchaseLeave = v.id;
            end
        end
    end
end

--[[
    清空增购信息
--]]
function ConfigService:clearIncreasePurchase()
    self.purchaseLeave = 100;
end


function ConfigService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "CONF_LIST_GAME_ROOM_CLIENT" then
        local resp = self:decode("ListGameRoomResp", msgData);
        self.roomConfigs = resp.data;
        table.sort(self.roomConfigs, function(a, b) return a.minGold < b.minGold end);
        log.net("房间数据", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Config_RoomConfigs);
    elseif msgName == "CONF_LSIT_MATCH_ROOM" then
        local resp = self:decode("ListMatchRoomResp", msgData);
        self.arenaConfigs = resp.data;
        log.net("比赛配置", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Config_ArenaConfigs);
    elseif msgName == "CONF_LSIT_MATCH_BLIND" then
        local resp = self:decode("ListMatchBlindResp", msgData);
        log.net("盲注配置", coli.log.dumpTable(resp));
        if resp.data[1] then
            self:saveArenaBlindConfigs(resp.data[1].id, resp.data);
        end
        coli.eventManager.notify(coli.Events.E_Config_ArenaBlindConfigs, resp);
    elseif msgName == "CONF_LSIT_MATCH_ENTRYFEE" then
        
        local resp = self:decode("ListMatchEntryFeeResp", msgData);
        --[resp.data[1].id] = resp.data;
        self:saveEnterFree(resp.data);
        log.net("报名消耗配置", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Config_ArenaCostConfigs, resp);
    elseif msgName == "CONF_LSIT_MATCH_REWARD" then
        local resp = self:decode("ListRewardResp", msgData);
        if  self:isSuccess(resp.resultCode) then
            log.net("奖励配置", coli.log.dumpTable(resp));
            coli.eventManager.notify(coli.Events.E_Config_ArenaRewardConfigs, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "CONF_LIST_SIGNIN" then
        local resp = self:decode("ListSignInRsp", msgData);
        log.net("签到配置", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Config_SignInConfigs, resp);
    elseif msgName == "CONF_LIST_BASE_SERVICE_CONFIG" then
        local resp = self:decode("ListBaseServiceConfigResp", msgData);
        log.net("所有通用配置", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Config_CommonConfigs, resp);
    elseif msgName == "CONF_LIST_BASE_SERVICE_CONFIG_BY_TYPE" then
        local resp = self:decode("ListBaseServiceConfigByTypeResp", msgData);
        if  self:isSuccess(resp.resultCode) then
            log.net("指定通用配置", coli.log.dumpTable(resp));
            coli.eventManager.notify(coli.Events.E_Config_CommonConfigByType, resp);
        else
            self:handleError(resp.resultCode);
        end
    end
end

--[[
    获取经典场房间名称
--]]
function ConfigService:getRoomName(roomId)
    local roomConfig = self:findRoomConfig(roomId);
    if roomConfig ~= nil then
        return roomConfig.roomName;
    end
    return "";
end

--[[
    获取MTT锦标赛房间名称
--]]
function ConfigService:getMTTRoomName(roomId)
    local roomConfig = self:findArenaConfigByRoomId(roomId);
    if roomConfig ~= nil then
        return roomConfig.name;
    end
    return "";
end

-- 数据相关
-- 获取房间所需费用
function ConfigService:getEnterFree(freeId)
    if enterFree[freeId] ~= nil then
        return enterFree[freeId];
    else
        self:reqArenaSignupCostConfigs(freeId)
    end
end

function ConfigService:saveEnterFree(data)
    if data[1] ~= nil  then
        enterFree[data[1].id] = data;
    end
end

-- 普通房间相关
function ConfigService:getRoomConfigs()
    return self.roomConfigs;
end

function ConfigService:getArenaConfigs()
    return self.arenaConfigs;
end

function ConfigService:saveArenaBlindConfigs(id, data)
    if self.arenaBlindConfigs == nil then
        self.arenaBlindConfigs = {};
    end
    self.arenaBlindConfigs[id] = data;
end

function ConfigService:getArenaBlindConfigs(id)
    if self.arenaBlindConfigs ~= nil and self.arenaBlindConfigs[id] ~= nil then
        return self.arenaBlindConfigs[id];
    else
        self:reqArenaBlindConfigs(id)
    end
  
end

-- 定时赛在当天的时候显示
function ConfigService:getRecentlyArena()
    local configs = self:getArenaConfigs();
    
    local index = 1;
    for i = 1, #configs do
        if self:getArenaLastTime(configs[i]) < self:getArenaLastTime(configs[index])  and self:getArenaLastTime(configs[i]) > 0 then
            index = i;
        end
    end
    -- 没有可以报名的比赛
    if self:getArenaLastTime(configs[index]) < 0 then
        return nil;
    end
    local recentlyArena = configs[index];
    for i = 2, #configs do
        local tempLastTime = self:getArenaLastTime(configs[i]);
        if tempLastTime > 0 then
            if self:getArenaLastTime(recentlyArena) > tempLastTime then
                recentlyArena = configs[i];
            end
        end
    end
    return recentlyArena;
end

function ConfigService:getArenaLastTime(config)
    if config.startTimeType ~= 1 then -- 每日赛
        local lastTime  = self:getAllTime(config.startTime) - self:getAllTime(os.time());
        if lastTime < 0 then
            -- 今天过了，就算到明天的时间
            lastTime = lastTime + 24 * 60 * 60;
        end
        return lastTime;
    else
        return  config.startTime - os.time();
    end
end

--[[
    把时间戳转换为今天0点到现在经过的秒数
--]]
function ConfigService:getAllTime(time)
    local hour = tonumber(os.date("%H", time));
    local minute = tonumber(os.date("%M", time));
    local second = tonumber(os.date("%S", time));
    return hour * 60 * 60 + minute * 60 + second;
end

function ConfigService:findRoomConfig(roomId)
    for _,v in ipairs(self.roomConfigs) do
        if v.roomID == roomId then
            return v;
        end
    end
end

-- 根据自身筹码数匹配最佳房间
function ConfigService:findBestRoomFromChips(gold)
    table.sort(self.roomConfigs, function(a, b) return a.minGold < b.minGold end);

    local finalIdx = 1;
    
    for i,v in ipairs(self.roomConfigs) do
        if v.fastGold > gold then
            break;
        else
            finalIdx = i;
        end
    end

    return self.roomConfigs[finalIdx];
end

-- 根据自身筹码数匹配最佳房间列表
function ConfigService:findBestRoomFromChipsList(gold)
    local roomConfig = self:findBestRoomFromChips(gold);
    local roomList = {};

    for i,v in ipairs(self.roomConfigs) do
        if roomConfig.fastGold == v.fastGold then
            table.insert(roomList, v);
        end
    end

    local matchSort = function(a, b)
        local peopleNumA = coli.ctx:parseRoomPeople(a.roomID);
        local peopleNumB = coli.ctx:parseRoomPeople(b.roomID);

        if peopleNumA < peopleNumB then
            return true;
        elseif peopleNumA == peopleNumB then
            local roomTypeA = coli.ctx:parseRoomSportsType(a.roomID);
            local roomTypeB = coli.ctx:parseRoomSportsType(b.roomID);
            return roomTypeA < roomTypeB;
        else
            return false;
        end
    end

    table.sort(roomList, matchSort);

    return roomList;
end

function ConfigService:findBestRoomConfig(gold)
    table.sort(self.roomConfigs, function(a, b) return a.minGold < b.minGold end);
    local finalIdx = 1;
    local currentRoom = self:getCurrentRoom(gold);
    if currentRoom ~= nil then
        return currentRoom;
    else
        for i, v in ipairs(self.roomConfigs) do
            if v.fastGold > gold then
                break ;
            else
                finalIdx = i;
            end
        end
        return self.roomConfigs[finalIdx];
    end
end

function ConfigService:getCurrentRoom(gold)
    if coli.ctx.curNormalRoomId ~= nil then
        local lastRoomConfig ;
        for i, v in ipairs(self.roomConfigs) do
            
            if v.roomID == coli.ctx.curNormalRoomId then
                lastRoomConfig = v;
                break ;
            end
        end
        -- 本次金币足够进入上次进入的房间才推荐进入房间
        if lastRoomConfig and lastRoomConfig.minGold <= gold then
            return lastRoomConfig;
        end
    end
end

---- 赛事相关
function ConfigService:findArenaConfig(arenaId)
    for i,v in ipairs(self.arenaConfigs) do
        if v.id == arenaId then
            return v;
        end
    end
    log.net("not find arena", arenaId, coli.log.dumpTable(self.arenaConfigs));
end

function ConfigService:findArenaConfigByRoomId(roomId)
    for i,v in ipairs(self.arenaConfigs) do
        if v.roomID == roomId then
            return v;
        end
    end
end

function ConfigService:toTypeName(type)
    if type == "E_MATCH_TYPE_MTT" then
        return "MTT";
    elseif type == "E_MATCH_TYPE_SNG" then
        return "SNG";
    end
    return "";
end

function ConfigService:findBlindConfigByLevel(level, id)
    if id == nil then
      id =  self:findArenaConfig(coli.ctx.curArenaId).blindID;
    end
    return self.arenaBlindConfigs[id][level];
end

function ConfigService:getBlindConfig(id)
    if  self.arenaBlindConfigs ~= nil then
        return self.arenaBlindConfigs[id];
    else
        return nil
    end
   
end


-- 请求
function ConfigService:createCommonMsg(msgName)
    local msgId = self:enumVal("ActionName", msgName, "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    return self:createMsg(msgType, msgId);
end

-- 获取房间配置
function ConfigService:createRoomConfigMsg()
    return self:createCommonMsg("CONF_LIST_GAME_ROOM_CLIENT");
end

function ConfigService:reqRoomConfigs()
    local msg = self:createRoomConfigMsg();
    self:sendOne(msg);
end

-- 获取比赛配置
function ConfigService:createArenaConfigMsg()
    return self:createCommonMsg("CONF_LSIT_MATCH_ROOM");
end

function ConfigService:reqArenaConfigs()
    local msg = self:createArenaConfigMsg();
    self:sendOne(msg);
end

-- 获取盲注配置
function ConfigService:reqArenaBlindConfigs(blindGroupId)
    self:sendOne(self:creatBlindConfig(blindGroupId));
end

function ConfigService:creatBlindConfig(blindGroupId)
    local msgId = self:enumVal("ActionName", "CONF_LSIT_MATCH_BLIND", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("ListMatchBlindReq", {
        blindID = blindGroupId
    });
    return self:createMsg(msgType, msgId, req);
end

-- 获取报名费
function ConfigService:reqArenaSignupCostConfigs(costGroupId)
    self:sendOne(self:createCostConfigs(costGroupId));
end

-- 获取报名费信息
function ConfigService:createCostConfigs(costGroupId)
    local msgId = self:enumVal("ActionName", "CONF_LSIT_MATCH_ENTRYFEE", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("ListMatchEntryFeeReq", {
        entryFeeID = costGroupId
    });
    return self:createMsg(msgType, msgId, req);
end

-- 获取奖励
function ConfigService:reqArenaRewardConfigs(rewardGroupId)
    local msgId = self:enumVal("ActionName", "CONF_LSIT_MATCH_REWARD", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("ListRewardReq", {
        awardsID = rewardGroupId
    });
    self:sendOne(msgType, msgId, req);
end

-- 签到配置
function ConfigService:reqSignInConfigs()
    local msgId = self:enumVal("ActionName", "CONF_LIST_SIGNIN", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

-- 获取通用配置
function ConfigService:reqCommonConfigs()
    local msgId = self:enumVal("ActionName", "CONF_LIST_BASE_SERVICE_CONFIG", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

-- 获取指定类型的通用配置
function ConfigService:reqCommonConfigByType(type)
    local msgId = self:enumVal("ActionName", "CONF_LIST_BASE_SERVICE_CONFIG_BY_TYPE", "XGameProto");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("ListBaseServiceConfigByTypeReq", {
        serviceType = type
    });
    self:sendOne(msgType, msgId, req);
end

return ConfigService;