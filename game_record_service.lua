--[[
    游戏记录服务
--]]

local Service = require("services.service");
---@class GameRecordService
local Service = class("GameRecordService", Service);

function Service:ctor()
    Service.super.ctor(self, "SERVICE_TYPE_GAME_RECORD", "GameRecordProto");
end

function Service:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "GAME_RECORD_QS_USER_ACT_INFO_QUERY" then
        local resp = self:decode("QSUserActInfoResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_GameRecord_Classical, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "GAME_RECORD_KO_USER_ACT_INFO_QUERY" then
        local resp = self:decode("KOUserActInfoResp", msgData);
        log.net("KOUserActInfoResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_GameRecord_Arena, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "GAME_RECORD_PR_GAME_INFO_QUERY" then
        local resp = self:decode("PRGameInfoResp", msgData);
        log.net("PRGameInfoResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_GameRecord_PrResult, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "GAME_RECORD_PR_GAME_INFO_DELETE" then
        local resp = self:decode("PRDeleteGameInfoResp", msgData);
        log.net("PRDeleteGameInfoResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Privite_DeleteCardRecordResp, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "GAME_RECORD_AI_USER_BASE_INFO_QUERY" then
        local resp = self:decode("AIUserBaseInfoResp", msgData);
        log.net("AIUserBaseInfoResp:", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_AI_RecvBaseData, resp.data);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "GAME_RECORD_AI_USER_CARD_INFO_QUERY" then
        local resp = self:decode("AIUserCardInfoResp", msgData);
        log.net("AIUserCardInfoResp:", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_AI_RecvCardGroupData, resp.data);
        else
            self:handleError(resp.resultCode);
        end
    end
end

-- 获取用户经典模式记录
function Service:createClassicalUserRecordMsg(uid,type)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_QS_USER_ACT_INFO_QUERY", "XGameProto");
    local req = self:encode("QSUserActInfoReq", {
        uid = uid,
        roomType = type
    });
    return self:createMsg(msgType, msgId, req);
end

function Service:reqClassicalUserRecord(uid,type)
    uid = uid or coli.ctx.uid
    type = type or coli.configs.square.TYPE_GAME_DEZHOU
    local msg = self:createClassicalUserRecordMsg(uid,type)
    self:sendOne(msg)
end

-- 获取用户赛事模式记录
function Service:createArenaUserRecordMsg(uid)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_KO_USER_ACT_INFO_QUERY", "XGameProto");
    local req = self:encode("KOUserActInfoReq", {
        uid = uid,
        type = coli.consts.RoomType.MTT,
    });
    return self:createMsg(msgType, msgId, req);
end

function Service:reqArenaUserRecord(uid)
    uid = uid or coli.ctx.uid;
    local msg = self:createArenaUserRecordMsg(uid);
    self:sendOne(msg);
end

-- 获取用户生涯SNG排位赛模式记录
function Service:createCareerSngUserRecordMsg(uid)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_KO_USER_ACT_INFO_QUERY", "XGameProto");
    local req = self:encode("KOUserActInfoReq", {
        uid = uid,
        type = coli.consts.RoomType.SNG,
    });
    return self:createMsg(msgType, msgId, req);
end

function Service:reqCareerSngUserRecord(uid)
    uid = uid or coli.ctx.uid;
    local msg = self:createCareerSngUserRecordMsg(uid);
    self:sendOne(msg);
end

-- 获取私人房牌局记录
function Service:createPrRoomRecordMsg(prType, clubID)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_PR_GAME_INFO_QUERY", "XGameProto");
    local req = self:encode("PRGameInfoReq", {
        type = prType or 0,
        clubId = clubID or 0,
    });
    return self:createMsg(msgType, msgId, req);
end

function Service:reqPrGameRecord(type, clubID)
    local msg = self:createPrRoomRecordMsg(type, clubID);
    self:sendOne(msg);
end

-- 删除私人房牌局记录
function Service:reqDelPrGameRecord(roomKey, iGameTime, clubID)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_PR_GAME_INFO_DELETE", "XGameProto");
    local data = {
        sRoomKey = roomKey,
        lclubId = clubID or 0,
        lGameTime = iGameTime,
    };
    local req = self:encode("PRDeleteGameInfoReq", data);
    log.net("reqDelPrGameRecord params:", log.dumpTable(data));
    self:sendOne(msgType, msgId, req);
end

--查询AI场用户基础信息
function Service:reqAIUserBaseInfo()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_AI_USER_BASE_INFO_QUERY", "XGameProto");
    print("reqAIUserBaseInfo");
    self:sendOne(msgType, msgId);
end

--查询AI场用户牌信息
function Service:reqAIUserCardInfo()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "GAME_RECORD_AI_USER_CARD_INFO_QUERY", "XGameProto");
    print("reqAIUserCardInfo");
    self:sendOne(msgType, msgId);
end

return Service;