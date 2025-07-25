--[[
    比赛服务
--]]

local Service = require("services.service");
---@class ArenaService
local ArenaService = class("ArenaService", Service);
-- 赛事是否结束的状态保存
local matchStates = {};
-- 赛事房间里的数据保存
local matchData = {};
-- 奖池的数量
local totalPool = {};
function ArenaService:ctor()
    ArenaService.super.ctor(self, "SERVICE_TYPE_MATCH", "matchProto");
    self.sngBlindConfigs = {};
    self.sngRewardConfigs = {};
end

function ArenaService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    log.net("msgName", msgName, msgId);
    if msgName == "MATCH_SIGN_UP" then
        local resp = self:decode("SignUpResp", msgData);
        log.net("SignUpResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) or resp.resultCode == 1201 then
            coli.eventManager.notify(coli.Events.E_Arena_SignUpSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_QUIT" then
        local resp = self:decode("QuitResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Arena_SignOutSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_USER_SIGN_UP_FLAG" then
        local resp = self:decode("UserSignUpFlagResp", msgData);
        log.net("报名信息", coli.log.dumpTable(resp));
        -- 保存用户报名状态
        if self.flag == nil then
            self.flag = {};
        end
        self.flag[resp.matchID] = resp.flag;
        
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Arena_SignUpStatus, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_PLAYER_INFO" then
        local resp = self:decode("PlayerInfoResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Arena_JoinArenaPlayers, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_JACKPOT" then
        local resp = self:decode("JackpotResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            totalPool[resp.matchID] = resp.value;
            coli.eventManager.notify(coli.Events.E_Arena_TotalPool, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_GAME_INFO" then
        local resp = self:decode("GameInfoResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self.currentBlindLevel = resp.gameInfo.blindLevel;
            matchStates[resp.matchID] = resp.gameInfo.matchState;
            matchData[resp.matchID] = resp.gameInfo;
            coli.eventManager.notify(coli.Events.E_Arena_GameInfo, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_USER_SIGN_UP_INFO" then
        local resp = self:decode("UserSignUpInfoResp", msgData);
        log.net(coli.log.dumpTable(resp));
        -- 保存用户状态
        self.userState = resp.info.userState;
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Arena_SignUpInfo, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "MATCH_LIST_MATCH_REWARD" then
        local resp = self:decode("ListRewardResp", msgData);
        log.net("ListRewardResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Arena_Rewards, resp);
        else
            self:handleError(resp.resultCode);
        end
-------------------------------------------------------- SNG --------------------------------------------------------
    elseif msgName == "E_SNG_INFO_LIST_RESP" then
        local resp = self:decode("SNGGetInfoListResp", msgData);
        log.net("SNGGetInfoListResp", log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self:saveSngData(resp.infos);
            self.sngInfos = resp.infos;
            coli.eventManager.notify(coli.Events.E_SNG_Info_List, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "E_SNG_CONFIG_RESP" then
        local resp = self:decode("SNGConfigResp", msgData);
        log.net("SNGConfigResp", log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self.sngConfigData = self.sngConfigData or {};
            
            local sngBlindConfigs = resp.blindConfigs;
            local sngRewardConfigs = {};
            for i,v in ipairs(resp.rewardConfigs) do
                local rewards = {};
                for _,v2 in ipairs(v.rewards) do
                    if v2.rewardId ~= 0 then
                        table.insert(rewards, v2);
                    end
                end
                v.rewards = rewards;
                table.insert(sngRewardConfigs, v);
            end
            self.sngBlindConfigs = sngBlindConfigs;
            self.sngRewardConfigs = sngRewardConfigs;
            self.sngConfigData[resp.matchId] = { sngBlindConfigs = sngBlindConfigs, sngRewardConfigs = sngRewardConfigs };
            -- coli.eventManager.notify(coli.Events.E_SNG_Process_Config, resp);
        else
            self:handleError(resp.resultCode);
        end
    -------------------------------------------------------- AI --------------------------------------------------------
    elseif msgName == "E_AI_PROCESS_ROOM_LIST_RESP" then
        local resp = self:decode("AIProcessRoomListResp", msgData);
        log.net("AIProcessRoomListResp", log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self:saveAiRoomInfo(resp.infos);
            coli.eventManager.notify(coli.Events.E_AI_RoomListInfo, resp);
        else
            self:handleError(resp.resultCode);
        end
    end
end

function ArenaService:handleNotify(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    log.net("ArenaService:handleNotify", msgName);
end

--[[
    获取是否可以进入赛事房间
--]]
function ArenaService:canEnterRoomDetail(matchID)
    if matchStates[matchID] ~= nil then
        return  matchStates[matchID] ~= "MATCH_STATE_END";
    else
        return false; -- 没有赛事id证明消息有问题
    end
end

function ArenaService:getArenaState(matchID)
    return  matchStates[matchID];
end

-- 获取当前所在比赛是否开赛
function ArenaService:getCurrentArenaIsBegin()
    return  matchStates[coli.ctx.curArenaId] == "MATCH_STATE_PLAYING_GAME";
end

--[[
    获取参赛数据
--]]
function ArenaService:getArenaData(matchID)
    return  matchData[matchID];
end

--[[
    参赛奖池
--]]
function ArenaService:getTotalPool(matchID)
    return totalPool[matchID];
end

function ArenaService:getSelfFlag(arenaId)
    return self.flag[arenaId or coli.ctx.curArenaId];
end

function ArenaService:getArenaSigninFlag(arenaId)
    return self.flag[arenaId];
end

-- Data
function ArenaService:getCurrentBlindLevel()
    return self.currentBlindLevel;
end

--[[
    @bindleave: 盲注级别
--]]
function ArenaService:getMatchIncreasePurchase()
    log.net("limitLevel",self.limitLevel);
    log.net("self.currentBlindLevel",self.currentBlindLevel);
    if self.limitLevel ~= nil and self.currentBlindLevel ~= nil then
        return self.limitLevel < self.currentBlindLevel;
    else -- 没有收到配置信息，使用默认没有到增购阶段
        return false;
    end
end

function ArenaService:getMatchPurchase()
    local lastPurchaseLevel =  self.purchaseLastLevel;
    if lastPurchaseLevel ~= nil and self.currentBlindLevel ~= nil  then
        return lastPurchaseLevel < self.currentBlindLevel;
    else -- 没有收到配置信息，使用默认没有到增购阶段
        return false;
    end
end

function ArenaService:getUserStatus()
    return self.userState;
end

function ArenaService:getBlindConfigs()
    return self.blindConfigs;
end



--------------------------------------------------------SNG--------------------------------------------------------
function ArenaService:getSNGInfo(matchID)
    if not self.sngConfigData then
        return false;
    end
    return self.sngConfigData[matchID];
end

function ArenaService:saveSngData(infos)
    self.sng9Infos = {};
    self.sng3Infos = {};
    for i, v in ipairs(infos) do
        local roomNumber = coli.ctx:parseRoomPeople(v.roomID)
        if  roomNumber == 9  then
            -- 9
            table.insert(self.sng9Infos, v);
        elseif roomNumber == 3 then
           table.insert(self.sng3Infos, v); 
        end
    end
    print("sng 9 infos", coli.log.dumpTable(self.sng9Infos));
end

function ArenaService:getSNG9Infos()
    return self.sng9Infos;
end

function ArenaService:getSNGInfos()
    return self.sngInfos;
end

function ArenaService:getSNG3Infos()
    return self.sng3Infos;
end

function ArenaService:getSNGInfoByUserNum(useNum)
    local roomTable = {};
    for _,v in ipairs(self.sngInfos) do
        if v.startGamePeople == useNum then
            table.insert(roomTable, v);
        end
    end
    return roomTable;
end

function ArenaService:findSNGByRoomID(roomID, matchId)
    for _,v in ipairs(self.sngInfos) do
        if v.matchId == matchId then
            return v;
        end
    end
end

function ArenaService:findSNGInfoById(matchId)
    for _,v in ipairs(self.sngInfos) do
        if v.matchId == matchId then
            return v;
        end
    end
end

function ArenaService:findSNGBlindConfigByLevel(level)
    local info = {level = 0, minBlind = 0, maxBlind = 0, frondBlind = 0, raiseTime = 0};
    for _,v in ipairs(self.sngBlindConfigs) do
        if v.level == level then
            return v;
        end
    end
    
    if #self.sngBlindConfigs > 0 then
        info = self.sngBlindConfigs[#self.sngBlindConfigs];
    end
    return info;
end

function ArenaService:getSNGRewardConfigs()
    return self.sngRewardConfigs;
end

function ArenaService:getSNGBlindConfigs()
    return self.sngBlindConfigs;
end

function ArenaService:clearSNGGameCache()
    self.sngBlindConfigs = {};
    self.sngRewardConfigs = {};
end
--------------------------------------------------------SNG End--------------------------------------------------------



--------------------------------------------------------AI DATA--------------------------------------------------------
function ArenaService:saveAiRoomInfo(info)
    self.aiCacheRoomInfo = info;
    table.sort(self.aiCacheRoomInfo, function(a,b) return a.takenIn < b.takenIn; end);
end

function ArenaService:getAiRoomInfo()
    return self.aiCacheRoomInfo;
end

function ArenaService:findAiByBlindIndex(index)
    for i,v in ipairs(self.aiCacheRoomInfo) do
        if v.blindLevel == tonumber(index) then
            return v;
        end
    end
end

function ArenaService:getAiTokenList()
    local tokenList = {};
    if self.aiCacheRoomInfo == nil  then
        return tokenList;
    end
    for i,v in ipairs(self.aiCacheRoomInfo) do
        table.insert(tokenList, {Smallbind = v.smallBlind, Bigblind = v.bigBlind});
    end
    table.sort(tokenList, function(a,b) return a.Smallbind < b.Smallbind; end);
    return tokenList;
end


function ArenaService:getExtRuleTokenInfo(index)
    local roomInfo = self.aiCacheRoomInfo;
    local single = roomInfo[1];
    for i,v in ipairs(roomInfo) do
        if index == i then
            single = v;
            break;
        end
    end
    return single;
end

function ArenaService:getExtRuleToSmallBigBlind(smallBlind, bigBlind)
    local roomInfo = self.aiCacheRoomInfo;
    local single = roomInfo[1];
    for i,v in ipairs(roomInfo) do
        if smallBlind == v.smallBlind and bigBlind == v.bigBlind then
            single = v;
            break;
        end
    end
    return single;
end
--------------------------------------------------------AI END--------------------------------------------------------



-- 获取重购最后阶段
-- 超出该阶段将没有重购功能
function ArenaService:findRepurchaseLastLevel(datas)
    local level = 0;
    for i,v in ipairs(datas) do
        if v.repurchase == 1 and i > level then
            level = i;
        end
    end
    self.limitLevel = level;
    return level;
end

-- 获取增购所在阶段
function ArenaService:findAdditionBeforeLevel(datas)
    local level = 0;
    for i,v in ipairs(datas) do
        if v.increasePurchase == 1 then
            level = math.max(i-1, 1);
        end
    end
    return level;
end

function ArenaService:findPurchaseLastLevel(datas)
    local level = 0;
    for i,v in ipairs(datas) do
        if v.purchase == 1 and i > level then
            level = i;
        end
    end
    self.purchaseLastLevel = level;
    return level;
end

-- 请求
-- 报名比赛
function ArenaService:reqSignUp(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_SIGN_UP", "XGameProto");
    local req = self:encode("SignUpReq", {
        matchID = matchId
    });
    self:sendOne(msgType, msgId, req);
end

-- 取消报名
function ArenaService:reqSignOut(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_QUIT", "XGameProto");
    local req = self:encode("QuitReq", {
        matchID = matchId
    });
    self:sendOne(msgType, msgId, req);
end

-- 查看玩家报名情况
function ArenaService:createCheckSignUpStatusMsg(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_USER_SIGN_UP_FLAG", "XGameProto");
    local req = self:encode("UserSignUpFlagReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqCheckSignUpStatus(matchId)
    self.reqMatchId = matchId;
    local msg = self:createCheckSignUpStatusMsg(matchId);
    self:sendOne(msg);
end

-- 获取参赛的玩家列表
function ArenaService:reqJoinArenaPlayers(matchId)
    self:sendOne(self:createJoinArenaPlayers(matchId));
end

function ArenaService:createJoinArenaPlayers(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_PLAYER_INFO", "XGameProto");
    local req = self:encode("PlayerInfoReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

-- 获取总奖池
function ArenaService:createTotalPoolMsg(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_JACKPOT", "XGameProto");
    local req = self:encode("JackpotReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqTotalPool(matchId)
    local msg = self:createTotalPoolMsg(matchId);
    self:sendOne(msg);
end

-- 获取游戏信息
function ArenaService:createGameInfoMsg(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_GAME_INFO", "XGameProto");
    local req = self:encode("GameInfoReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqGameInfo(matchId)
    log.net("reqGameInfo", matchId);
    local msg = self:createGameInfoMsg(matchId);
    self:sendOne(msg);
end

-- 获取报名信息
function ArenaService:createSignUpInfoMsg(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_USER_SIGN_UP_INFO", "XGameProto");
    local req = self:encode("UserSignUpInfoReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqSignUpInfo(matchId)
    local msg = self:createSignUpInfoMsg(matchId);
    self:sendOne(msg);
end


-- 获取比赛奖励列表
function ArenaService:createArenaRewardsMsg(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "MATCH_LIST_MATCH_REWARD", "XGameProto");
    local req = self:encode("ListRewardReq", {
        matchID = matchId
    });
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqArenaRewards(matchId)
    self:sendOne(self:createArenaRewardsMsg(matchId));
end


-- 获取SNG相关信息
function ArenaService:createGetSNGRoomListMsg(roomType, roomSubType)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "E_SNG_INFO_LIST_REQ", "XGameProto");
    local req = self:encode("SNGGetInfoListReq", {});
    return self:createMsg(msgType, msgId, req);
end

function ArenaService:reqSNGInfo(roomType, roomSubType)
    self:sendOne(self:createGetSNGRoomListMsg());
end


-- 获取排名
function ArenaService:reqSNGGetRankingList(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "E_SNG_PROCESS_RANKING_LIST_REQ", "XGameProto");
    local req = self:encode("SNGProcessRankingListReq", {
        matchId = matchId
    });
    self:sendOne(msgType, msgId, req);
end

-- 刷新排名
function ArenaService:reqSNGRefreshRankingList(matchId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "E_SNG_PROCESS_REFRESH_RANKING_LIST_REQ", "XGameProto");
    local req = self:encode("SNGProcessRankingListReq", {
        matchId = matchId
    });
    self:sendOne(msgType, msgId, req);
end

-- 赛事配置
function ArenaService:reqSNGConfig(matchId, tableId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "E_SNG_CONFIG_REQ", "XGameProto");
    local req = self:encode("SNGConfigReq", {
        matchId = matchId,
        tableId = tableId,
    });
    log.net("reqSNGConfig", matchId, tableId);
    self:sendOne(msgType, msgId, req);
end

function ArenaService:getMatchStatus(arenaID)
    local status = coli.consts.MatchStatus.none;
    local matchState =  self:getArenaState(arenaID);
    if matchState == "MATCH_STATE_DEFAULT" then
        -- 比赛没开始
        if self:getSelfFlag() == 1 then
            -- 已报名
            status = coli.consts.MatchStatus.waitStart;
        else
            if self:getArenaData(arenaID).isfull then
                print("end Signin", "比赛没开始满员了");
                -- 满员
                status = coli.consts.MatchStatus.endSignin;
            else
                status = coli.consts.MatchStatus.canSignin;
            end
        end
    elseif matchState == "MATCH_STATE_PLAYING_GAME" then
        -- 比赛中
        status = self:getPlayingStatue(arenaID);
    elseif matchState == "MATCH_STATE_END" then
        -- 比赛结束
        status = coli.consts.MatchStatus.playEnd;
    else
        status = coli.consts.MatchStatus.none;
    end
    return status;
end

-- 比赛进行中
function ArenaService:getPlayingStatue(arenaID)
    local status = coli.consts.MatchStatus.none;
    if self:getSelfFlag() == 1 then
        if coli.serviceManager.koService:isWatching() then
            status = coli.consts.MatchStatus.canRePurchase;
        else
            -- 比赛中 
            status = coli.consts.MatchStatus.playing;
        end
    elseif self:getSelfFlag() == 2 then
        -- 被淘汰  重购/报名
        status = coli.consts.MatchStatus.weedOut;
    else
        -- 未报名
        if self:getMatchPurchase() then
            -- 过了重购阶段 报名已截止
            status = coli.consts.MatchStatus.endSignin;
        else
            if self:getArenaData(arenaID).isfull then
                -- 满员 报名已截止
                status = coli.consts.MatchStatus.endSignin;
            else  -- 报名
                status = coli.consts.MatchStatus.canDelaySignin;
            end
        end
    end
    return status;
end

--[[
    AI 挑战赛相关协议请求
--]]
-- AI房间列表
function ArenaService:createGetAiRoomListMsg()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "E_AI_PROCESS_ROOM_LIST_REQ", "XGameProto");
    return self:createMsg(msgType, msgId);
end

function ArenaService:reqAiRoomList()
    self:sendOne(self:createGetAiRoomListMsg());
end

-- return require("services.mock.mock_arena_service")(ArenaService);
return ArenaService;