--[[
    聊天服务
--]]

local Service = require("services.service");
---@class ChatService
local ChatService = class("ChatService", Service);

function ChatService:ctor()
    ChatService.super.ctor(self, "SERVICE_TYPE_CHAT", "ChatProto")

    self.gameRoomChatDatas = {}; -- 游戏房间聊天缓存
end

function ChatService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "QUERY_CHAT_RECORDS" then
        local resp = self:decode("QueryChatRecordsResp", msgData);
        log.net(coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            table.sort(resp.records, function(a, b)
                return a.time < b.time;
            end);
            coli.eventManager.notify(coli.Events.E_Chat_ChatRecords, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "CHAT_UPDATE_RECORDS" then
        local resp = self:decode("UpdateChatRecordsResp", msgData);
        log.net("UpdateChatRecordsResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Chat_UpdateChatRecordStateSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "QUERY_USERLIST_CHAT_RECORDS" then
        local resp = self:decode("QueryUserListChatRecordsResp", msgData);
        log.net("QueryUserListChatRecordsResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Chat_QueryFriendsChatRecordsSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    end
end

function ChatService:handleNotify(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "CHAT_PRIVATE" then
        local resp = self:decode("ChatPrivateResp", msgData);
        log.net("ChatPrivateResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Chat_SendChatMsg, resp);
        else
            self:handleError(resp.resultCode);
        end
    end
end

-- 数据
function ChatService:recordGameRoomChatMsg(data)
    if data.iChatType ~= 1 then
        return; --只存文字聊天
    end
    if #self.gameRoomChatDatas > 30 then
        table.remove(self.gameRoomChatDatas,1);
    end
    table.insert(self.gameRoomChatDatas, data);
    coli.eventManager.notify(coli.Events.E_Chat_RefreshChatUI,data);
end

function ChatService:getGameRoomChatMsgList()
    return self.gameRoomChatDatas;
end

function ChatService:resetChatMsg()
    self.gameRoomChatDatas = {};
end

-- 请求

-- 查询聊天记录
function ChatService:reqQueryChatRecords(targetUid)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "QUERY_CHAT_RECORDS", "XGameProto");
    local req = self:encode("QueryChatRecordsReq", {
        friend_uid = targetUid
    });
    self:sendOne(msgType, msgId, req);
end

-- 发送聊天信息
function ChatService:reqSendChatMsg(targetUid, msg, msgType)
    msgType = msgType or 0;
    local msgId = self:enumVal("ActionName", "CHAT_PRIVATE", "XGameProto");
    local req = self:encode("ChatPrivateReq", {
        friend_uid = targetUid,
        msg = msg,
        msgType = msgType,
    });
    self:sendOne(msgType, msgId, req);
end

--function ChatService:parseChatInfo(inofo)
--    
--end

-- 请求更新聊天记录是否可读的标签
function ChatService:reqUpdateChatRecordState(friendUid, recordInfos)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "CHAT_UPDATE_RECORDS", "XGameProto");
    local req = self:encode("UpdateChatRecordsReq", {
        friend_uid = friendUid,
        records = recordInfos,
    });
    log.net("friend_uid = ", friendUid, ", Records = ",coli.log.dumpTable(recordInfos));
    self:sendOne(msgType, msgId, req);
end

-- 请求当前所有聊天好友的聊天记录
function ChatService:reqQueryFriendsChatRecords(uids)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "QUERY_USERLIST_CHAT_RECORDS", "XGameProto");
    local req = self:encode("QueryUserListChatRecordsReq", {
        uidList = uids
    });
    self:sendOne(msgType, msgId, req);
end

return ChatService;