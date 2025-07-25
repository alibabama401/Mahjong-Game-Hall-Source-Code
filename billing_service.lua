--[[
--[[
    订单服务
--]]

local Service = require("services.service");
---@class BilldingService
local BilldingService = class("BilldingService", Service);

function BilldingService:ctor()
    BilldingService.super.ctor(self, "SERVICE_TYPE_ORDER", "orderProto");
    self.isSandBox = Runtime.AppConfiguration.Instance.Current.IsSandBox;
end

function BilldingService:handleResponse(msgType, msgId, msgData)
    local msgName = self:enumName("ActionName", msgId, "XGameProto");
    if msgName == "ORDER_YIELD" then
        local resp = self:decode("OrderYieldResp", msgData);
        log.net("生成订单号", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            if resp.type == "E_CHANNEL_IOS" then
                -- Apple内购
                log.net("coli.SDKMain:inAppPurchase - ios");
                -- coli.SDKMain:inAppPurchase(resp.orderNum, resp.product_id);
                local receiptJson = {}; 
                receiptJson["receipt-data"] = self.receipt;

                local params = {
                    orderNum = resp.orderNum,
                    credential = cjson.encode(receiptJson),
                    transaction_id = self.transation_id
                };
                log.net(coli.log.dumpTable(params));
                self:reqVerifyOrder(params);
            elseif resp.type == "E_CHANNEL_GOOGLEPLAY" then
                -- Google内购
                self.orderNum = resp.orderNum;
                --3.收到服务端的返回
                -- 4.给服务端发送token，包名,oderid,产品id
                log.net("coli.SDKMain:inAppPurchase - google");
                local receiptJson = {};
                receiptJson["packageName"] = self.packageName;
                receiptJson["productId"] = resp.product_id;
                receiptJson["token"] = self.token;
                local params = {
                    orderNum = resp.orderNum,
                    credential = cjson.encode(receiptJson),
                    transaction_id = ""
                };
                log.net(coli.log.dumpTable(params));
                self:reqVerifyOrder(params);
            end
        else
            coli.utils.hideNetLoading();
            self:handleError(resp.resultCode);
        end
    elseif msgName == "ORDER_VERRITY" then
        local resp = self:decode("OrderVerifyResp", msgData);
        log.net("OrderVerifyResp 验证订单", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            coli.SDKMain:finishPay(resp.identity);
            coli.eventManager.notify(coli.Events.E_Billing_VerifySuccess, resp);
        else
            coli.SDKMain:finishPay(resp.identity);
            self:handleError(resp.resultCode);
        end
        coli.utils.hideNetLoading();
    elseif msgName == "ORDER_CONSUME" then
        local resp = self:decode("ConsumptionVerifyResp", msgData);
        log.net("ConsumptionVerifyResp 消费订单", coli.log.dumpTable(resp));
        if self:isSuccess(resp.resultCode) then
            self:removeOrderID(resp.orderNum);
            coli.eventManager.notify(coli.Events.E_Billing_VerifySuccess, resp);
        else
            self:removeOrderID(resp.orderNum);
            self:handleError(resp.resultCode);
        end
    end
end

--[[
     在支付成功的时候记录订单id
--]]

function BilldingService:recoreOrderID(id)
    local ids = self:getOderID()
    ids[#ids + 1] = id;
    local idStr = cjson.encode(ids);
    coli.db.pay.setOderId(idStr);
end

--[[
    订单结束的时候移除订单id
--]]
function BilldingService:removeOrderID(id)
    local ids = self:getOderID();
    for i, v in pairs(ids) do
        if v  == id then
            table.remove(ids,i);
        end
    end
    local idStr = cjson.encode(ids);
    coli.db.pay.setOderId(idStr);
end

--[[
    在sdkmain中移除恢复订单
--]]
function BilldingService:getOderID()
    local idStr = coli.db.pay.getOderId();
    if idStr == nil or idStr == "" then
        return {};
    end
    return cjson.decode(idStr);
end
-- 请求
-- 生成订单号
function BilldingService:reqCreateOrder(type, productId, qrCode, isSandBox)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "ORDER_YIELD", "XGameProto");
    local req = self:encode("OrderYieldReq", {
        type = type,
        isSandBox = isSandBox,
        product_id = productId,
        qrCode = qrCode,
    });
    log.net("reqCreateOrder", type, isSandBox, productId, qrCode);
    self:sendOne(msgType, msgId, req);
end

function BilldingService:reqCreateGoogleOrder(type, productId, qrCode, isSandBox, googleOrderNum)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "ORDER_YIELD", "XGameProto");
    local req = self:encode("OrderYieldReq", {
        type = type,
        isSandBox = isSandBox,
        product_id = productId,
        qrCode = qrCode,
        google_order_num = googleOrderNum,
    });
    log.net("reqCreateGoogleOrder", type, isSandBox, productId, qrCode, googleOrderNum);
    self:sendOne(msgType, msgId, req);
end

-- 生成订单号
function BilldingService:reqVerifyOrder(params)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "ORDER_VERRITY", "XGameProto");
    local req = self:encode("OrderVerifyReq", params);
    self:sendOne(msgType, msgId, req);
end

function BilldingService:reqConsume(oderId)
    local msgType = coli.netService.MSGTYPE_REQUEST;
    local msgId = self:enumVal("ActionName", "ORDER_CONSUME", "XGameProto");
    log.net("oderId",oderId);
    local req = self:encode("ConsumptionVerifyReq", { orderNum = oderId });
    self:sendOne(msgType, msgId, req);
end

return BilldingService;