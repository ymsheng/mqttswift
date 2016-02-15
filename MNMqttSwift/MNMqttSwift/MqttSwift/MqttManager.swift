//
//  MqttManager.swift
//  BossSwift
//
//  Created by mosn on 1/8/16.
//  Copyright © 2016 com.hpbr.111. All rights reserved.
//

import Foundation

enum MQTTManagerConnectType:Int{
    case MQTTManagerConnectTypeIng          = 1
    case MQTTManagerConnectTypeConnect      = 2
    case MQTTManagerConnectTypeDisconnect   = 3
    case MQTTManagerConnectTypeClose        = 4
}

let PRESENCE_MID:Double = 1

public class MqttManager:NSObject,MQTTSessionDelegate {
    //是否连接着聊天服务器(对外只读)
    private(set) public var isConnected: Bool?
    var mqttClient:MQTTSession!
    private var connectType:MQTTManagerConnectType?
    
    
    //单例
    static let sharedInstance = MqttManager()
    
    //MARK: - connect
    func connectMQTT() -> Bool {
        
        if let user = getUserIdentifier() {
            let name:String = String(format: "%d-%d-%@",user.uid,getUserCurrentType(),APP_PROTOCOL_VERSION)
            let time = NSDate().timeIntervalSince1970
            let timeStr:String = String(format:"%@%.0f",user.secretKey,time)
            let password:String = String(format:"%@%.0f",timeStr.md5StringFor16().uppercaseString,time)
            if self.mqttClient != nil {
                self.mqttClient.close()
            }
            self.mqttClient = MQTTSession(theClientId: OpenUDID.getOpenUDID().md5StringFor16(), theUserName: name, thePassword: password, theKeepAliveInterval: 40, theCleanSessionFlag: true)
            self.connectType = .MQTTManagerConnectTypeIng
            
            self.mqttClient.delegate = self
            
            weak var weakSelf = self as MqttManager
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                weakSelf!.mqttClient.connectToHost(APP_MQTT_HOST, port: APP_MQTT_PORT)
            })
        }
        
        
        return  false
    }
    
    func disconnectMQTT(again:Int) {
        if self.mqttClient != nil {
            self.mqttClient.associatedObject = NSNumber(int: Int32(again))
            self.mqttClient.close()
        }
    }
    
    func connectToHost() {
        if self.mqttClient != nil {
            self.connectType = .MQTTManagerConnectTypeIng
            //WARNING:这里后面要加入第一次登陆的设置
            self.mqttClient.delegate = self
            weak var weakSelf = self as MqttManager
            dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                weakSelf!.mqttClient .connectToHost(APP_MQTT_HOST, port: APP_MQTT_PORT)
            }
        }else {
            MqttManager.sharedInstance.connectMQTT()
        }
    }
    
    func subscribe(topic:String) {
        self.mqttClient.subscribeTopic(topic, qosLevel: 0)
    }
    
    
    //MARK: send
    func sendMQTTMessage(msg:MessageProtocol) -> Bool {
        if self.mqttClient != nil {
            let data = encodingProtocol(msg)
            if data != nil && data!.length > 0 {
                var mid:Double? = 0
                if msg.messages != nil && msg.messages!.count > 0 {
                    let body = msg.messages!.objectAtIndex(0) as! MessageInfo
                    mid = Double(body.mid!)
                }
                else if msg.protocolType == .ProtocolTypePresence {
                    mid = PRESENCE_MID
                }
                dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                    //WARNING:添加发送的消息到数据库
                }
                self.mqttClient.publishDataExactlyOnce(data!, topic:"chat", retainFlag: true, mid: mid!)
                return true
            }
        }
        return false
    }
    //MARK: send read
    func sendReadMQTTMessage(msgItem:MessageProtocol,index:String) ->Bool {
        if self.mqttClient != nil {
            let data = encodingProtocol(msgItem)
            if msgItem.messages != nil && msgItem.messages!.count > 0 {
                self.mqttClient.publishDataExactlyOnce(data!, topic: "chat", retainFlag: true, indexStr: index)
            }
            return true
        }
        return false
    }
    
    func sendPresence() {
        let pro:MessageProtocol = MessageProtocol.init(preInfo: Presence.init(ptype: .PresenceTypeOnline, WithReachType: "WIFI", WithMsgId: 0))
        sendMQTTMessage(pro)
    }
    
    
    //MARK: - delegate
    func sessionHandleEvent(session:MQTTSession, eventCode:MQTTSessionEvent) {
        if self.isConnected != (eventCode == .MQTTSessionEventConnected) {
            self.isConnected = (eventCode == .MQTTSessionEventConnected)
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                NSNotificationCenter.defaultCenter().postNotificationName(kChatServerConnect, object: nil)
            })
        }
        switch eventCode {
        case .MQTTSessionEventConnected:
            sendPresence()
            DLog("connected")
            self.connectType = .MQTTManagerConnectTypeConnect
            sendPresence()
            //WARNING:发送本地未读
            //[[MessageReadHandler sharedReadMessageHandler] sendLocalReadMessage];
        case .MQTTSessionEventConnectionRefused:
            DLog("refrused")
            self.connectType = .MQTTManagerConnectTypeDisconnect
            if getUserIdentifier() != nil {
                //WARNING:这里要弹出alert
                DLog("您的身份已过期，请重新登录")
            }
            setUserIdentifier(nil)
            disconnectMQTT(0)
            appdelegate.initRootViewController()
        case .MQTTSessionEventConnectionClosed:
            DLog("closed")
            if self.mqttClient != nil {
                self.mqttClient.delegate = nil
            }
            self.connectType = .MQTTManagerConnectTypeClose
            if let again:Int = self.mqttClient.associatedObject as? Int {
                if again == 1 {
                    self.mqttClient.deallocSession()
                    self.mqttClient = nil
                    connectMQTT()
                    self.mqttClient.associatedObject = NSNumber(int: 0)
                }
            }
            else {
                self.mqttClient = nil
            }
        case .MQTTSessionEventConnectionError:
            DLog("error")
            if self.connectType?.rawValue < 3 {
                self.connectType = .MQTTManagerConnectTypeDisconnect
                DLog("connection error")
                DLog("reconnecting...after 5s...")
                weak var weakSelf = self as MqttManager
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(5 * Double(NSEC_PER_SEC))),dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
                    weakSelf?.mqttClient.deallocSession()
                    if weakSelf?.mqttClient != nil && weakSelf?.connectType == .MQTTManagerConnectTypeDisconnect {
                        weakSelf?.connectType = .MQTTManagerConnectTypeIng
                        //WARNINT:theApp.isLanuchFirst = NO;
                        weakSelf?.mqttClient .connectToHost(APP_MQTT_HOST, port: APP_MQTT_PORT)
                    }
                })
            }
        case .MQTTSessionEventProtocolError:
            DLog("protocol error")
            self.connectType = .MQTTManagerConnectTypeDisconnect
        }
    }
    func sessionNewMessageOnTopic(session:MQTTSession, data:NSData, topic:String) {
        let queue:dispatch_queue_t = dispatch_queue_create("SaveRecMessageList", nil)
        dispatch_async(queue) { () -> Void in
            //WARNING: [[MessageHandler sharedMessageHandler] messageAppend:[AppConfig convertDataToMessage:data]];
            DLog(decodingProtocol(data))
        }
    }
    func sessionCompletionMidWithStatus(session:MQTTSession, mid:Double, status:SendStatus) {
        if floor(mid) == PRESENCE_MID && status == .SendStatusFailed {
            //self.sendPresence()
        }else {
            //WARNING:更新数据库
        }
    }
    func sessionCompletionIndex(session:MQTTSession, index:String) {
        //WARNING:更新数据库
        //[[MessageReadHandler sharedReadMessageHandler] setReadSuccess:Index];
    }
}