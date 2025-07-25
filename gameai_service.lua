
local coli = coli or {}
local Service = require("services.service");
---@class GameAiService
local GameAiService = class("GameAiService", Service);

local SEAT_COUNT = 2;

local STATE_NORMAL = 0;
local STATE_REENTER = 1;
local STATE_WATCH = 2;

function GameAiService:ctor()
    GameAiService.super.ctor(self, "SERVICE_TYPE_DEFAULT", "XGameAi");
    self.tablePlayers = {};
end

function GameAiService:onClear()

end

function GameAiService:handleRequest(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Ai_Msgid", msgId);
end

function GameAiService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Ai_Msgid", msgId);
    if msgName == "E_AI_MSGID_LOGIN_ROOM_RESP" then    -- 登录房间响应
        local resp = self:decode("TAiMsgRespLoginRoom", msgData);
        log.net("AI场 TAiMsgRespLoginRoom", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.ctx:setCurrentDeskType(coli.consts.DeskType.E_AI);
            self:clearPlayers();
            self:sitdown();
            coli.eventManager.notify(coli.Events.E_AI_Login_Room);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_AI_MSGID_SITDOWN_RESP" then    -- 坐下桌子响应
        local resp = self:decode("TAiMsgRespSitDown", msgData);
        log.net("AI场 TAiMsgRespSitDown", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            if coli.ctx.uid == resp.lPlayerID then
                coli.ctx:EnterTheGame();
            end
            coli.eventManager.notify(coli.Events.E_AI_Sitdown, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_AI_MSGID_EXIT_RESP" then       -- 退出房间响应
        local resp = self:decode("TAiMsgRespExit", msgData);
        log.net("AI场 TAiMsgRespExit", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.eventManager.notify(coli.Events.E_AI_Exit_Room);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_AI_MSGID_WATCH_RESP" then      -- 请求观战响应
        local resp = self:decode("TAIMsgRespWatchGame", msgData);
        log.net("AI 场 TAIMsgRespWatchGame", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.eventManager.notify(coli.Events.E_AI_EnterWatchGame, resp);
            coli.ctx:EnterTheGame();
        else
            self:handleError(resp.iResultID);
        end
    end
end

function GameAiService:handleNotify(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Ai_Msgid", msgId);
    if msgName == "E_AI_MSGID_SITDOWN_NOTIFY" then      -- 坐下桌子通知
        local resp = self:decode("TAiMsgRespSitDown", msgData);
        log.net("AI场 TAiMsgRespSitDown Notify", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.eventManager.notify(coli.Events.E_AI_Sitdown_Room_Notify, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_AI_MSGID_EXIT_NOTIFY" then

    end
end

function GameAiService:addPlayer(resp)
    if resp.iChairID < 0 then
        return;
    end
    self:removePlayer(resp.lPlayerID);
    table.insert(self.tablePlayers, resp);
    self:sortPlayers();
end

function GameAiService:removePlayer(playerId)
    for i,v in ipairs(self.tablePlayers) do
        if v.lPlayerID == playerId then
            table.remove(self.tablePlayers, i);
            break;
        end
    end
    self:sortPlayers();
end

function GameAiService:updatePlayerChairId(playerId, chairId)
    for i,v in ipairs(self.tablePlayers) do
        if v.lPlayerID == playerId then
            v.iChairID = chairId
            break;
        end
    end
    self:sortPlayers();
end

function GameAiService:sortPlayers()
    table.sort(self.tablePlayers, function(a, b)
        return a.iChairID > b.iChairID;
    end);
end

function GameAiService:findPlayerByChairID(chairId)
    local p = nil;
    for _,tp in ipairs(self.tablePlayers) do
        if tp.iChairID == chairId then
            p = tp;
            break;
        end
    end
    return p;
end

function GameAiService:findPlayerByUID(uid)
    local p = nil;
    for _,tp in ipairs(self.tablePlayers) do
        if tp.lPlayerID == uid then
            p = tp;
            break;
        end
    end
    return p;
end

function GameAiService:getPlayers()
    return self.tablePlayers;
end

function GameAiService:clearPlayers()
    self.tablePlayers = {};
end

function GameAiService:checkReenter()
    return self.currentState == STATE_REENTER;
end

function GameAiService:markReenter()
    self.currentState = STATE_REENTER;
end

function GameAiService:reenterCompleted()
    self.currentState = STATE_NORMAL;
end

function GameAiService:markWatching()
    self.currentState = STATE_WATCH;
end

function GameAiService:isWatching()
    return self.currentState == STATE_WATCH;
end

function GameAiService:cancelWatching()
    self.currentState = STATE_NORMAL;
end

function GameAiService:setLoginRoomData(datas)
    self.loginRoomDatas = datas;
end

function GameAiService:getLoginRoomDatas()
    return self.loginRoomDatas or {};
end

function GameAiService:getMaxSeat()
    print("getMaxSeat = ", SEAT_COUNT);
    return SEAT_COUNT;
end

function GameAiService:quickStart()
    local chip = coli.serviceManager.userService:getMyself():getGold();

    local quickStartGame = function(config)
        if not config then
            coli.utils.showTip(gettext("筹码不足"));
            return;
        end

        coli.ctx.curBlindLevel = config.blindLevel;
        coli.ctx.curTableId = 0;
        coli.ctx.curRoomId = config.roomID;
        coli.serviceManager.aiService:loginRoom();
        UIHelper.ShowNetLoadingWithType(coli.enum.NetLoadingType.EnterGame)
    end

    local getDefaultConf = function()
        local aiConfigs = coli.serviceManager.arenaService:getAiRoomInfo();
        local conf = nil;
        for i=#aiConfigs,1,-1 do
            local info = aiConfigs[i];
            if info.takenIn <= chip then
                conf = info;
                break;
            end
        end
        return conf;
    end

    local localInfo = coli.db.tableScreening.getSquareTableScreeningInfo(coli.configs.square.TYPE_GAME_AI);

    if string.len(localInfo) > 0 then
        local str = string.split(localInfo, ":");
        local tokenIndex = tonumber(str[3]) + 1;
        local conf = coli.serviceManager.arenaService:getExtRuleTokenInfo(tokenIndex);
        if conf.takenIn > chip then
            conf = getDefaultConf();
        end

        quickStartGame(conf);
    else
        local conf = getDefaultConf();

        quickStartGame(conf);
    end
end

--- 请求

-- 请求进入房间
function GameAiService:enterRoom(pwd)
    local msgId = self:enumVal("Eum_Ai_Msgid", "E_AI_MSGID_ENTER_ROOM_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

-- 请求离开房间
function GameAiService:reqExitRoom()
    local msgId = self:enumVal("Eum_Ai_Msgid", "E_AI_MSGID_EXIT_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

-- 请求坐下桌子
function GameAiService:sitdown(bAutoSit, iChairID)
    local msgId = self:enumVal("Eum_Ai_Msgid", "E_AI_MSGID_SITDOWN_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("TAiMsgReqSitDown", {
        bAutoSit    = bAutoSit or true,
        iChairID    = iChairID or -1,
        smallBlind  = 0,
        bigBlind    = 0,
        takenIn     = 0,
        iTableID    = coli.ctx.curTableId,
        iBlindLevel = coli.ctx.curBlindLevel,
    });
    
    -- 备注: 目前德扑1v1 下面几个参数已无效, 但这里暂时不删除
    --[[
        smallBlind  = 0,
        bigBlind    = 0,
        takenIn     = 0,
    --]]
    log.net("AI sitdown curBlindLevel:", coli.ctx.curBlindLevel);
    self:sendOne(msgType, msgId, req);
end

-- 请求登录房间
function GameAiService:loginRoom()
    local msgId = self:enumVal("Eum_Ai_Msgid", "E_AI_MSGID_LOGIN_ROOM_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

-- 请求观战
function GameAiService:reqEnterAiWatching(bSelfSelect)
    local msgId = self:enumVal("Eum_Ai_Msgid", "E_AI_MSGID_WATCH_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("TAIMsgReqWatchGame", {
        iTableID = coli.ctx.curTableId,
        bSelfSelect = bSelfSelect or true,
    });
    log.net("reqEnterAiWatching coli.ctx.curTableId", coli.ctx.curTableId);
    self:sendOne(msgType, msgId, req);   
end


return GameAiService;