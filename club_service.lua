local BaseService = require("services.service");
---@class ClubService
local Service = class("ClubService", BaseService);

local MSG_Name = {
    CLUB_INFO_CREATE_CLUB                = "CLUB_INFO_CREATE_CLUB",           --创建俱乐部      √
    CLUB_INFO_DISSOLVE_CLUB              = "CLUB_INFO_DISSOLVE_CLUB",         --解散俱乐部
    CLUB_INFO_UPDATE_CLUB                = "CLUB_INFO_UPDATE_CLUB",           --更新俱乐部      √
    CLUB_INFO_LIST_CLUB                  = "CLUB_INFO_LIST_CLUB",             --获取俱乐部列表   √
    CLUB_INFO_JOIN_CLUB                  = "CLUB_INFO_JOIN_CLUB",             --加入俱乐部      √
    CLUB_INFO_LIST_USER_APPLY            = "CLUB_INFO_LIST_USER_APPLY",       --获取用户申请列表 √
    CLUB_AUDIT_APPLY                     = "CLUB_AUDIT_APPLY",                --审核入会请求
    CLUB_INFO_LIST_ALL_USER              = "CLUB_INFO_LIST_ALL_USER",         --获取成员列表     √
    CLUB_INFO_KICKOUT_USER               = "CLUB_INFO_KICKOUT_USER",          --踢出成员 
    CLUB_INFO_EXIT_CLUB                  = "CLUB_INFO_EXIT_CLUB",             --退出俱乐部
    CLUB_INFO_GET_INFO                   = "CLUB_INFO_GET_INFO",              -- 获取俱乐部基本信息
};

local ResponseCB = {}; -- {msgName, fun}
function Service:ctor()
    Service.super.ctor(self, "SERVICE_TYPE_CLUB", "ClubProto");
end

function Service:handleResponse(sgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    for _, v in ipairs(ResponseCB) do
        if v.msgName == msgName then 
            v.fun(msgData);
        end
    end
end

function Service:handleNotify(sgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "ACHIEVEMENT_TOUCH" then          --sng 触发成就
        local notify = self:decode("AchievementInfoNotify", msgData);
        log.net("Notify AchievementInfoNotify", log.dumpTable(notify));
        self:saveAchievementInfo(notify);
    end
end

function Service:addListenResp(key, fun)
    local isAdd = true;
    for _, v in ipairs(ResponseCB) do 
        if v.msgName == key then 
            isAdd = false;
            break;
        end
    end
    if isAdd then 
        table.insert( ResponseCB, { msgName = key, fun = fun } );
    end
end

function Service:removeListenResp(key)
    for i, v in ipairs(ResponseCB) do
        if v.msgName == key then 
            table.remove( ResponseCB, i );
        end
    end
end

------------------------------------------------------------- 俱乐部协议相关 -------------------------------------------------------------------
-- 创建俱乐部
function Service:reqCreateClub(head, name, content)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_CREATE_CLUB, "XGameProto");
    local data = {clubAvatar = head, clubName = name, clubNotice = content};
    local req = self:encode("CreateClubReq", data);
    log.net(MSG_Name.CLUB_INFO_CREATE_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_CREATE_CLUB, function(msgData) self:respCreateClub(msgData) end)
end
function Service:respCreateClub(msgData)
    --log.net("respCreateClub", log.dumpTable(msgData) );
    self:removeListenResp(MSG_Name.CLUB_INFO_CREATE_CLUB);
    local resp = self:decode("CreateClubResp", msgData);
    log.net("CreateClubResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.createClubController:destroy();
        self:_reqCurChoiceList();
    else
        self:handleError(resp.resultCode);
    end
end
-- 解散俱乐部
function Service:reqDissolveClub()
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_DISSOLVE_CLUB, "XGameProto");
    local data = {clubId = self.homepageController.clubID};
    local req = self:encode("DissolveClubReq", data);
    log.net(MSG_Name.CLUB_INFO_DISSOLVE_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_DISSOLVE_CLUB, function(msgData) self:respDissolveClub(msgData) end)
end
function Service:respDissolveClub(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_DISSOLVE_CLUB);
    local resp = self:decode("DissolveClubResp", msgData);
    log.net("DissolveClubResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.homepageController:destroy();
        self:_reqCurChoiceList();
    else
        self:handleError(resp.resultCode);
    end
end
-- 更新俱乐部
function Service:reqUpdateClub(id, head, name, content )
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_UPDATE_CLUB, "XGameProto");
    local data = {clubId = id, clubAvatar = head, clubName = name, clubNotice = content};
    local req = self:encode("UpdateClubReq", data);
    log.net(MSG_Name.CLUB_INFO_UPDATE_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_UPDATE_CLUB, function(msgData) self:respUpdateClub(msgData) end)
end
function Service:respUpdateClub(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_UPDATE_CLUB);
    local resp = self:decode("UpdateClubResp", msgData);
    log.net("UpdateClubResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.createClubController:destroy();
        self.homepageController:setData(resp.clubInfo);
        self:_reqCurChoiceList();
    else
        self:handleError(resp.resultCode);
    end
end
-- 获取俱乐部列表
function Service:reqClubList(filter, index)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_LIST_CLUB, "XGameProto");
    local data = {clubFilter = filter, pageIndex = index};  -- 过滤条件（1 已创建 2:已经加入)
    local req = self:encode("ClubListReq", data);
    log.net(MSG_Name.CLUB_INFO_LIST_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_LIST_CLUB, function(msgData) self:respClubList(msgData) end)
end
function Service:respClubList(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_LIST_CLUB);
    local resp = self:decode("ClubListResp", msgData);
    log.net("ClubListResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.clubController:respCreateClubList(resp);
    else
        self:handleError(resp.resultCode);
    end
end
-- 获取俱乐部基本信息
function Service:reqClubInfo(clubID)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_GET_INFO, "XGameProto");
    local data = {clubId = clubID};
    local req = self:encode("GetClubInfoReq", data);
    log.net(MSG_Name.CLUB_INFO_GET_INFO, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_GET_INFO, function(msgData) self:respClubInfo(msgData) end);
end
function Service:respClubInfo(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_GET_INFO);
    local resp = self:decode("GetClubInfoResp", msgData);
    log.net("GetClubInfoResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.joinClubController:respClubInfo(resp.clubInfo);
    else
        self:handleError(resp.resultCode);
    end
end
-- 加入俱乐部
function Service:reqJoinClub(clubID)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_JOIN_CLUB, "XGameProto");
    local data = {clubId = clubID};
    local req = self:encode("ApplyJoinClubReq", data);
    log.net(MSG_Name.CLUB_INFO_JOIN_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_JOIN_CLUB, function(msgData) self:respJoinClub(msgData) end);
end
function Service:respJoinClub(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_JOIN_CLUB);
    local resp = self:decode("ApplyJoinClubResp", msgData);
    log.net("ApplyJoinClubResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.joinClubController:respJoinSuccess();
    else
        self:handleError(resp.resultCode);
    end
end
-- 申请入会列表俱乐部
function Service:reqClubApplyList(clubID, index )
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_LIST_USER_APPLY, "XGameProto");
    local data = {clubId = clubID, pageIndex = index};
    local req = self:encode("ClubApplyListReq", data);
    log.net(MSG_Name.CLUB_INFO_LIST_USER_APPLY, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_LIST_USER_APPLY, function(msgData) self:respClubApplyList(msgData) end);
end
function Service:respClubApplyList(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_LIST_USER_APPLY);
    local resp = self:decode("ClubApplyListResp", msgData);
    log.net("ClubApplyListResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.batchClubController:updateBatchListView(resp);
    else
        self:handleError(resp.resultCode);
    end
end
-- 批准入会俱乐部
function Service:reqClubAudit(targetUid, agree)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_AUDIT_APPLY, "XGameProto");
    local data = { clubId = self.batchClubController.clubData.clubId, targetUid = targetUid, agree = agree };
    local req = self:encode("AuditApplyReq", data);
    log.net(MSG_Name.CLUB_AUDIT_APPLY, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_AUDIT_APPLY, function(msgData) self:respClubAudit(msgData) end)
end
function Service:respClubAudit(msgData)
    self:removeListenResp(MSG_Name.CLUB_AUDIT_APPLY);
    local resp = self:decode("AuditApplyResp", msgData);
    log.net("AuditApplyResp", log.dumpTable(resp));
    self:reqClubApplyList(resp.clubId, 1);
    self:_reqCurChoiceList();
    if self:isSuccess(resp.resultCode) then 
        coli.utils.showTip( resp.agree and gettext("已通过审核") or gettext("已拒绝加入"));        
    else
        self:handleError(resp.resultCode);
    end
end
--  成员列表俱乐部
function Service:reqMemberList(clubID, index)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_LIST_ALL_USER, "XGameProto");
    local data = { clubId = clubID, pageIndex = index };
    local req = self:encode("ClubMemberListReq", data);
    log.net(MSG_Name.CLUB_INFO_LIST_ALL_USER, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_LIST_ALL_USER, function(msgData) self:respMemberList(msgData) end)
end
function Service:respMemberList(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_LIST_ALL_USER);
    local resp = self:decode("ClubMemberListResp", msgData);
    log.net("ClubMemberListResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.homepageController:updateMemberListView(resp);
    else
        self:handleError(resp.resultCode);
    end
end
-- 踢出成员
function Service:reqKickOut(targetUid)
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_KICKOUT_USER, "XGameProto");
    local data = { clubId = self.homepageController.clubID, targetUid = targetUid };
    local req = self:encode("KickClubMemberReq", data);
    log.net(MSG_Name.CLUB_INFO_KICKOUT_USER, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_KICKOUT_USER, function(msgData) self:respKickOut(msgData) end)
end
function Service:respKickOut(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_KICKOUT_USER);
    local resp = self:decode("KickClubMemberResp", msgData);
    log.net("KickClubMemberResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self:reqMemberList(resp.clubId, 1);
    else
        self:handleError(resp.resultCode);
    end
end
-- 退出俱乐部
function Service:reqQuitClub()
    local msgId = self:enumVal("ActionName", MSG_Name.CLUB_INFO_EXIT_CLUB, "XGameProto");
    local data = { clubId = self.homepageController.clubID };
    local req = self:encode("ExitClubReq", data);
    log.net(MSG_Name.CLUB_INFO_EXIT_CLUB, msgId, log.dumpTable(data) );

    self:sendReq(msgId, req);
    self:addListenResp(MSG_Name.CLUB_INFO_EXIT_CLUB, function(msgData) self:respQuitClub(msgData) end)
end
function Service:respQuitClub(msgData)
    self:removeListenResp(MSG_Name.CLUB_INFO_EXIT_CLUB);
    local resp = self:decode("ExitClubResp", msgData);
    log.net("ExitClubResp", log.dumpTable(resp));
    if self:isSuccess(resp.resultCode) then 
        self.homepageController:destroy();
        self:_reqCurChoiceList();
    else
        self:handleError(resp.resultCode);
    end
end


-----------------------------------------------------------------------------------------------------------------------------------
---更新当前选中标签数据
function Service:_reqCurChoiceList()
    if self.clubController:isSelectType(coli.configs.club.Select_Creater) then -- 如果当前选中创建标签则刷新
        self:reqClubList(1, 1);
    elseif self.clubController:isSelectType(coli.configs.club.Select_Join) then
        self:reqClubList(2, 1);
    end
end

-------------------------------------------------------------- 数据相关 ----------------------------------------------------------------------------
function Service:setClubController(controller)
    self.clubController = controller;
    return self;
end

function Service:setCreateClubController(controller)
    self.createClubController = controller;
    return self;
end

function Service:setJoinClubController(controller)
    self.joinClubController = controller;
    return self;
end

function Service:setBatchClubController(controller)
    self.batchClubController = controller;
    return self;
end

function Service:setHomePageController(controller)
    self.homepageController = controller;
    return self;
end

function Service:clearData()
    self.clubController = nil;
    self.createClubController = nil;
    self.joinClubController = nil;
    self.batchClubController = nil;
end


return Service;