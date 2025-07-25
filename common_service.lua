--[[
    通用服务类
    用于处理通用的网络命令，如心跳，Ping等等。
--]]

local Service = require("services.service");
---@class CommonService
---@field userService UserService
local CommonService = class("CommonService", Service);
function CommonService:ctor()
    CommonService.super.ctor(self, "SERVICE_TYPE_DEFAULT", "XGameComm");
    self.invitePlayerList = {};
    self.inviteFriendList = {};
    self.isNoviceTag = false;
    self.regTime = 0;
end

function CommonService:onClear()
    self.timesampsMap = nil;
    self.invitePlayerList = nil;
    self.inviteFriendList = nil;
end

function CommonService:onAccumulator(loginTime)
    --- |_____|______|
    --- t1    t2

    -- 第一次赋登陆返回的服务器时间
    self.serverTime = loginTime;
    self.accumulateTime = self.serverTime - loginTime;
    
    -- 时间差
    self.cliAndSvrDiffTime = self.serverTime - os.time();
end

function CommonService:getCurrentTime()
    return os.time() + self.cliAndSvrDiffTime;
end

function CommonService:getLocalTime(times)
    return times - self.cliAndSvrDiffTime;
end


function CommonService:getCumulativeTime()
    local elapsedTime = self:getCurrentTime() - self.serverTime;
    return elapsedTime;
end

function CommonService:handleRequest(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Comm_Msgid", msgId);
    if msgName == "E_MSGID_KEEP_ALIVE_REQ" then
        local respMsgID = self:enumVal("Eum_Comm_Msgid", "E_MSGID_KEEP_ALIVE_RESP");
        local tPack = self:createTPackage({
            playid = coli.ctx.playId,
            vecMsgHead = {{nMsgID = respMsgID, nMsgType = coli.netService.MSGTYPE_RESPONSE}}
        });
        self:send(tPack);
    end
end

function CommonService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Comm_Msgid", msgId);
    if msgName == "E_MSGID_LOGIN_HALL_RESP" then                            -- 重连成功
        local resp = self:decode("TMsgRespLoginHall", msgData, "XGameComm");
        log.net("TMsgRespLoginHall", coli.log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            print("TMsgRespLoginHall 公钥 ",resp.sPubKey)
            if resp.sPubKey and string.len(resp.sPubKey) > 0 then
                coli.ctx.publicKey = resp.sPubKey;
            else
                coli.ctx.publicKey = nil;
            end
            coli.ctx.isLogined = true;
            coli.eventManager.notify(coli.Events.E_Hall_Login_Success, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_MSGID_ROOM_INFO_RESP" then                         -- 房间信息
        local resp = self:decode("TMsgRespRoomInfo", msgData, "XGameComm");
        log.net("TMsgRespRoomInfo", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.ctx.curTableId = resp.iTableID;
            coli.eventManager.notify(coli.Events.E_GamePlay_RoomInfo, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_MSGID_INVITE_LIST_RESP" then                       -- 邀请玩家列表, 分为好友列表和在线玩家列表
        local resp = self:decode("TMsgRespGetInviteList", msgData);
        log.net("TMsgRespGetInviteList", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            self.invitePlayerList = {};
            self.inviteFriendList = {};
            for _,v in ipairs(resp.friendInfo) do
                v.type = 1;
                table.insert(self.inviteFriendList, v);
            end
            for _,v in ipairs(resp.playerInfo) do
                v.type = 2;
                table.insert(self.invitePlayerList, v);
            end
            table.sort(self.inviteFriendList, function(a, b) return a.lPlayerID > b.lPlayerID; end);
            table.sort(self.invitePlayerList, function(a, b) return a.lPlayerID > b.lPlayerID; end);
            coli.eventManager.notify(coli.Events.E_Qs_GetInviteList);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_MSGID_INVITE_PLAYER_RESP" then                     -- 邀请玩家成功
        local resp = self:decode("TMsgRespInvitePlayer", msgData);
        log.net("TMsgRespInvitePlayer", log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.eventManager.notify(coli.Events.E_Qs_InviteSuccess, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_MSGID_WATCH_RESP" then                             -- 观战列表返回
        local resp = self:decode("TMsgRespWatchList", msgData);
        log.net("TMsgRespWatchList", coli.log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            self:cacheWatchListTimestamp(resp.item);
            coli.eventManager.notify(coli.Events.E_GamePlay_Watch_List, resp);
        else
            self:handleError(resp.iResultID);
        end
    elseif msgName == "E_MSGID_WATCH_NOTIFY" then                           -- 邀请玩家坐下, 通知给被邀请的玩家
        local resp = self:decode("TMsgNotifyWatchInvite", msgData);
        log.net("TMsgNotifyWatchInvite", coli.log.dumpTable(resp));
        coli.tipManager:showPullDownTip({
            content = string.format(gettext("<color=#f1c429>%s</color>邀请你玩牌"), resp.sNickName),
            confirmCb = function()
                coli.serviceManager.gameplayService:reqSitdown(true, -1);
            end,
            cancelCb = function()
                coli.utils.showTip(string.format(gettext("你拒绝了%s的玩牌邀请"), resp.sNickName));
            end,
            type = coli.consts.PullDownTipType.ConfirmAndCancel,
            confirmTitle = gettext("接受"),
            cancelTitle = gettext("拒绝")
        });
        coli.eventManager.notify(coli.Events.E_GamePlay_InvitePlayerSitdown, resp);
    elseif msgName == "E_MSGID_KEEP_ALIVE_RESP" then                        -- 主动请求心跳
        coli.netServerStatusDetector:OnRecvPing()
        self.serverTime = msgData;
        self.cliAndSvrDiffTime = self.serverTime - os.time();
    elseif msgName == "E_MSGID_PROPS_INFO_RESP" then
        local resp = self:decode("TMsgRespProps", msgData);
        log.net("TMsgRespProps", coli.log.dumpTable(resp));
        coli.eventManager.notify(coli.Events.E_Chat_PropInfo, resp);
    end
end

function CommonService:handleNotify(msgType, msgId, msgData)
    local msgName = self:enumName("Eum_Comm_Msgid", msgId);
    if msgName == "E_MSGID_OFFLINE_NOTIFY" then -- 离线
        local resp = self:decode("TMsgRespOffline", msgData);
        coli.log.debug("TMsgRespOffline", resp.lPlayerID, resp.iChairID);
    elseif msgName == "E_MSGID_CHAT_TE_NOTIFY" then
        local resp = self:decode("TMsgRespChat", msgData, "XGameComm");
        log.net("TMsgRespChat", coli.log.dumpTable(resp));
        if self:isSuccess(resp.iResultID) then
            coli.eventManager.notify(coli.Events.E_Chat_SendChatMsgInGamePlay, resp);
        else
            if resp.iResultID == -3 then
                coli.utils.showTip(gettext("旁观状态无法发送"));
            else
                self:handleError(resp.iResultID);
            end
        end
    elseif msgName == "E_MSGID_CHAT_AUDIO_NOTIFY" then
        local notify = self:decode("TMsgRespAudioChat", msgData, "XGameComm");
        log.net("TMsgRespAudioChat", coli.log.dumpTable(notify));
        if self:isSuccess(notify.iResultID) then
            coli.eventManager.notify(coli.Events.E_Chat_ReadAudioChatNotify, notify);
        else
            self:handleError(notify.iResultID);
        end
    elseif msgName == "E_MSGID_SERVER_RESET_NOTIFY" then
        coli.utils.showTip(gettext("服务器重启"));
        coli.utils.hideMatchBeginTip();
        coli.eventManager.notify(coli.Events.E_Server_Reset);
    elseif msgName == "PUSH_CHAT_UPDATE" then
        coli.eventManager.notify(coli.Events.E_Chat_Change);
    end
end

-------------------------------------------------------  缓存数据 -------------------------------------------------------
--- 好友邀请列表, 时间是服务器缓存的
function CommonService:getFriendInviteList()
    return self.inviteFriendList or {};
end

function CommonService:getPlayerInviteList()
    return self.invitePlayerList or {};
end

function CommonService:updateInviteTimestamp(params)
    local refreshTimestamp = function(list)
        if list == nil then
            return;
        end
        for _,v in ipairs(list) do
            if params.lPlayerID == 0 or v.lPlayerID == params.lPlayerID then
                v.lTimestamp = params.lTimestamp;
                
                if params.lPlayerID ~= 0 then
                    break;
                end
            end
        end
    end

    refreshTimestamp(self.inviteFriendList);
    refreshTimestamp(self.invitePlayerList);
end

function CommonService:delFriendFromInviteList(uid)
    local friendList = self:getFriendInviteList();
    for i,v in ipairs(friendList) do
        if v.lPlayerID == uid then
            table.remove(friendList, i);
            break;
        end
    end
end

function CommonService:delPlayerFromInviteList(uid)
    local playerList = self:getPlayerInviteList();
    for i,v in ipairs(playerList) do
        if v.lPlayerID == uid then
            table.remove(playerList, i);
            break;
        end
    end
end

--- 观战列表, 冷却时间由客户端自己缓存
function CommonService:cacheWatchListTimestamp(playerList)
    self.timesampsMap = self.timesampsMap or {};
    for i,v in ipairs(playerList) do
        v.lTimestamp = self.timesampsMap[v.lPlayerID] or 0;
    end
end

function CommonService:updateWatchListTimestamp(params)
    self.timesampsMap[params.lPlayerID] = params.lTimestamp;
end

function CommonService:getWatchListTimestamp(uid)
    return self.timesampsMap[uid] or 0;
end


--[[
    param参数 
message TMsgRespChat
{
    sint32 iResultID = 1;	 //返回结果：0.成功
    sint32 iChatType = 2;	 //聊天类型 1.文本聊天, 2.表情聊天
    string sChatData = 3;	 //聊天数据内容
    sint32 iChairID  = 4;	 //玩家所在桌子位置
    string sName     = 5;    //发起者名字
};
--]]
function CommonService:saveChatData(param)
    if self.chatTable == nil then
        self.chatTable = {};
    end
    local chatData = {};
    chatData.sName =param.sName;
    chatData.sChatData = param.sChatData;
    chatData.iChatType = param.iChatType;
    chatData.sChatTime = self:getChatTime();
    if #self.chatTable >= 100 then
        table.remove(self.chatTable, 1);
    end
    table.insert(self.chatTable,chatData);
end

function CommonService:getChatData()
    if self.chatTable == nil  then
        return {};
    end
    return self.chatTable;
end

--[[
    退出游戏场景调用该方法
--]]
function CommonService:clearData()
    self.chatTable = {};
end

function CommonService:getChatTime()
    local time = os.date("%H:%M", os.time());
    --log.net(os.date("%Y-%m-%d %H:%M:%S", os.time()))
    --string.format("%02d:%02d",minuteTime,secondTime)
    return time;
end
------------------------------------------------------- 缓存数据 -------------------------------------------------------

-- 查询弹幕信息
function CommonService:reqBulletChatInfo()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_PROPS_INFO_REQ", "XGameComm");
    self:sendOne(msgType, msgId);
end

-- 发送场内弹幕信息
function CommonService:reqSendBarrage(msg, chatType, destChairId, propsId, bReward)
    if coli.db.setting.isOpenTableChat() then
       coli.utils.showTip(gettext("已屏蔽桌面聊天"));
        return;
    end
    log.net("chatType, propsId = ", chatType, propsId);
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_CHAT_TE_REQ", "XGameComm");
    local req = self:encode("TMsgReqChat", {
        iChatType = chatType,
        sChatData = msg,
        iDestChairId = destChairId,
        iPropsID = propsId,
        bReward = bReward or false,
    }, "XGameComm");
    self:sendOne(msgType, msgId, req);
end

-- 发送登录大厅验证
function CommonService:reqLoginHall()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_LOGIN_HALL_REQ", "XGameComm");
    self:sendOne(msgType, msgId);
end

-- 请求所在房间信息
function CommonService:getRoomInfo()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_ROOM_INFO_REQ", "XGameComm");
    self:sendOne(msgType, msgId);
end

-- 发送心跳
function CommonService:sendHeartBeat()
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_KEEP_ALIVE_REQ", "XGameComm");
    -- log.net("sendHeartBeat 发送心跳");
    coli.netServerStatusDetector:OnSendPing()
    self:sendOne(msgType, msgId);
end

-- 获取好友邀请列表
function CommonService:reqGetInvitePlayerList()
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_INVITE_LIST_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

function CommonService:reqInviteFriendPlayer(uid)
    self:reqInvite(uid, 1);
end

function CommonService:reqInvitePlayer(uid)
    self:reqInvite(uid, 2);
end

function CommonService:reqInviteWatchPlayer(uid)
    self:reqInvite(uid, 3);
end

-- 发起邀请(type: 1-邀请在线好友; 2-在线玩家; 3-旁观玩家)
function CommonService:reqInvite(uid, type)
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_INVITE_PLAYER_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("TMsgReqInvitePlayer", {
        lPlayerID = uid,
        iPlayerType = type
    });
    self:sendOne(msgType, msgId, req);
end

-- 获取观战列表
function CommonService:reqWatchList()
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_WATCH_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    self:sendOne(msgType, msgId);
end

function CommonService:reqAudioChat(sChatData,duration)
    local msgId = self:enumVal("Eum_Comm_Msgid", "E_MSGID_CHAT_AUDIO_REQ");
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local req = self:encode("TMsgReqAudioChat", {
        duration = duration,
        sChatData = sChatData,
    });
    log.net("E_MSGID_CHAT_AUDIO_REQ duration-- sChatData ", duration,"--",sChatData);
    self:sendOne(msgType, msgId, req);
end

return CommonService;