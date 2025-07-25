--[[
    好友服务
--]]

local Service = require("services.service");
---@class FriendService
local FriendService = class("FriendService", Service);

function FriendService:ctor()
    FriendService.super.ctor(self, "SERVICE_TYPE_FRIENDS", "FriendsProto");

    coli.eventManager.addObserver(self, coli.Events.E_Login_LogoutSuccess);
    self.friendList = {};
    self.notApprovedIds = {}; --客户端保存当前用户已点击添加好友,但未审批通过的好友uid,下线则清楚数据
end

function FriendService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "FRIENDS_ADD" then
        local resp = self:decode("AddFriendResp", msgData);
        log.net("AddFriendResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            table.insert(self.notApprovedIds, resp.friend_uid);
            coli.eventManager.notify(coli.Events.E_Friend_SendAddFriendSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_DELETE" then
        local resp = self:decode("DeleteFriendResp", msgData);
        log.net("DeleteFriendResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self:deleteFriend(resp.friend_uid);
            coli.eventManager.notify(coli.Events.E_Friend_DelFriendSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_QUERY" then
        local resp = self:decode("QueryFriendListResp", msgData);
        log.net("QueryFriendListResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self.friendList = resp.FriendList;
            self:clearAlyIdFromNotApproved();
            coli.eventManager.notify(coli.Events.E_Friend_QueryFriendListSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_QUERYAPPLICANT" then
        local resp = self:decode("QueryApplicantListResp", msgData);
        log.net("QueryApplicantListResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_QueryApplicationListSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_AGREETOADD" then
        local resp = self:decode("AgreeToAddResp", msgData);
        log.net("AgreeToAddResp", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_ProcessApplicationSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_ONLINE_NOTFRIEND_QUERY" then
        local resp = self:decode("QueryOnlineNotFriendListResp", msgData);
        log.net("推荐好友结果：", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_QueryOnlineNotFriendListSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_QUERY_GIVE_INFO" then
        local resp = self:decode("QueryFriendGiveInfoResp", msgData);
        log.net("赠送好友筹码信息：", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_QueryGiveChipsFriendListSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_CHAT_QUERY" then
        local resp = self:decode("QueryFriendListResp", msgData);
        log.net("聊天好友列表：", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_QueryChatFriendListSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    elseif msgName == "REMARK_ADD" then
        local resp = self:decode("AddRemarkResp", msgData);
        if self:isSuccess(resp.resultCode) then
            log.net("添加备注成功", resp.content);
            coli.eventManager.notify(coli.Events.E_Friend_DelPrivateChatFriendSuccess, resp);
        else
            log.net("添加备注失败", resp.resultCode);
            self:handleError(resp.resultCode);
        end
    elseif msgName == "FRIENDS_CHAT_DELETE" then
        local resp = self:decode("DeleteFriendResp", msgData);
        log.net("聊天好友删除：", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.eventManager.notify(coli.Events.E_Friend_DelPrivateChatFriendSuccess, resp);
        else
            self:handleError(resp.resultCode);
        end
    end
end

-- 从已点击添加好友中,清楚掉已经审批同意的uid
function FriendService:clearAlyIdFromNotApproved()
    for i=#self.notApprovedIds,1,-1 do
        if self:isFriend(self.notApprovedIds[i]) then
            table.remove(self.notApprovedIds, i);
        end
    end
end

-- 根据uid清楚审批确定后的uid
function FriendService:clearConfirmApprovedUid(uid)
    for i=#self.notApprovedIds,1,-1 do
        if self.notApprovedIds[i] == uid then
            table.remove(self.notApprovedIds, i);
            return;
        end
    end
end

-- 清空notApprovedIds
function FriendService:clearApprovedIds()
    self.notApprovedIds = {};
end

-- 推荐好友是否在未审批的列表里
function FriendService:isNotApproved(uid)
    for i,v in ipairs(self.notApprovedIds) do
        if v == uid then
            return true;
        end
    end
    return false;
end

-- 是否是好友
function FriendService:isFriend(uid)
    for i,v in ipairs(self.friendList) do
        if v == uid then
            return true;
        end
    end
    return false;
end

-- 删除好友
function FriendService:deleteFriend(uid)
    for i,v in ipairs(self.friendList) do
        if v == uid then
            table.remove(self.friendList, i);
            break;
        end
    end
end

function FriendService:handleNotify(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "FRIENDS_AGREETOADD_NOTICE" then
        local resp = self:decode("AgreeToAddNotice", msgData);
        log.net("AgreeToAddNotice", coli.log.traceback(resp));
        if resp.is_agree == 1 then
            coli.utils.showTip(string.format("%s %s", resp.friend_name, gettext("同意了你的好友请求")));
        else
            coli.utils.showTip(string.format("%s %s", resp.friend_name, gettext("拒绝了你的好友请求")))
        end

        self:clearConfirmApprovedUid(resp.friend_uid);
        self:reqQueryFriendList(); --收到好友审批通过后,更新一下好友uid列表
    end
end

function FriendService:handleEvent(event, params)
    if event == coli.Events.E_Login_LogoutSuccess then
        self:clearApprovedIds();
    end
end

-- 请求

-- 请求加好友
function FriendService:reqAddFriend(targetUid, msg)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_ADD", "XGameProto");
    local req = self:encode("AddFriendReq", {
        friend_uid = targetUid, 
        content = msg,
    });
    self:sendOne(msgType, msgId, req);
end

-- 请求删除好友
function FriendService:reqDelFriend(targetUid)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_DELETE", "XGameProto");
    local req = self:encode("DeleteFriendReq", {
        friend_uid = targetUid,
    });
    self:sendOne(msgType, msgId, req);
end

-- 查询好友列表
function FriendService:reqQueryFriendList()
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_QUERY", "XGameProto");
    self:sendOne(msgType, msgId);
end

-- 添加备注信息
function FriendService:reqAddRemark(uid,content)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "REMARK_ADD", "XGameProto");
    local req = self:encode("AddRemarkReq", {
        remark_uid = uid,
        content = content,
    });
    self:sendOne(msgType, msgId, req);
end

-- 屏蔽聊天,不看某人说的话
---@param forbit number 禁言为1,否则为0
function FriendService:reqForbitChat(uid,forbit)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FORBIT_CHAT", "XGameProto");
    local req = self:encode("ForbitChatReq", {
        forbit_uid = uid,
        is_forbit = forbit,
    });
    self:sendOne(msgType, msgId, req);
end

-- 查询请求列表
function FriendService:reqQueryApplicationList()
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_QUERYAPPLICANT", "XGameProto");
    log.info("FRIENDS_QUERYAPPLICANT req");
    self:sendOne(msgType, msgId);
end

-- 处理好友请求
function FriendService:reqProcessApplication(targetUid, isAgree)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_AGREETOADD", "XGameProto");
    local req = self:encode("AgreeToAddReq", {
        friend_uid = targetUid,
        is_agree = isAgree
    });
    self:sendOne(msgType, msgId, req);
end

-- 查询推荐玩家列表
function FriendService:reqQueryRecomPlayerList()
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_ONLINE_NOTFRIEND_QUERY", "XGameProto");
    self:sendOne(msgType, msgId);
end

-- 查询用户赠送好友的筹码信息,筹码每天只能赠送一次
function FriendService:reqFriendGiveInfo()
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_QUERY_GIVE_INFO", "XGameProto");
    self:sendOne(msgType, msgId);
end

-- 查询聊天好友列表
function FriendService:reqQueryFriendChatList()
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_CHAT_QUERY", "XGameProto");
    self:sendOne(msgType, msgId);
end

-- 请求删除聊天好友——私聊选择页面
function FriendService:reqDelPrivateChatFriend(uid)
    local msgType = coli.netService.MSGTYPE_REQUREST;
    local msgId = self:enumVal("ActionName", "FRIENDS_CHAT_DELETE", "XGameProto");
    local req = self:encode("DeleteFriendReq", {
        friend_uid = uid
    });
    self:sendOne(msgType, msgId, req);
end

return FriendService;