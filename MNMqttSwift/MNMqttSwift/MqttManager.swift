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
let MQTT_PORT:Int = 2345  //chat server port
let MQTT_HOST:String = "192.168.1.166"// "your chat ip"

public class MqttManager:NSObject,MQTTSessionDelegate {
    //是否连接着聊天服务器(对外只读)
    private(set) public var isConnected: Bool?
    var mqttClient:MQTTSession!
    private var connectType:MQTTManagerConnectType?
    
    
    //单例
    static let sharedInstance = MqttManager()
    
    //MARK: - connect
    func connectMQTT() -> Bool {
        if self.mqttClient != nil {
            self.mqttClient.close()
        }
        self.mqttClient = MQTTSession(theClientId: "34ED51F8581BAA60", theUserName:"8304-0-1.3", thePassword:"1B87519CF7A848341455593855", theKeepAliveInterval: 40, theCleanSessionFlag: true)
//        self.mqttClient = MQTTSession(theClientId: "your clinetId", theUserName:"user name", thePassword:"user password", theKeepAliveInterval: 40, theCleanSessionFlag: true)
        self.connectType = .MQTTManagerConnectTypeIng
        
        self.mqttClient.delegate = self
        
        weak var weakSelf = self as MqttManager
        dispatch_async(dispatch_get_main_queue(), { () -> Void in
            weakSelf!.mqttClient.connectToHost(MQTT_HOST, port: MQTT_PORT)
        })
        return true
    }
    
    ///go background call disconnect
    func disconnectMQTT() {
        if self.mqttClient != nil {
            self.mqttClient.close()
        }
    }
    
    ///go activi call connectToHost
    func connectToHost() {
        if self.mqttClient != nil {
            self.connectType = .MQTTManagerConnectTypeIng
            //WARNING:这里后面要加入第一次登陆的设置
            self.mqttClient.delegate = self
            weak var weakSelf = self as MqttManager
            dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                weakSelf!.mqttClient .connectToHost(MQTT_HOST, port: MQTT_PORT)
            }
        }else {
            MqttManager.sharedInstance.connectMQTT()
        }
    }
    
    func subscribe(topic:String) {
        self.mqttClient.subscribeTopic(topic, qosLevel: 0)
    }
    
    
    //MARK: send
    func sendMQTTMessage(data:NSData?) -> Bool {
        if self.mqttClient != nil {
            
            if data != nil && data!.length > 0 {
                
                dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0)) { () -> Void in
                    //WARNING:添加发送的消息到数据库
                }
                self.mqttClient.publishDataExactlyOnce(data!, topic:"chat", retainFlag: true, mid: 0) //mid设置为你发送消息的唯一标识
                return true
            }
        }
        return false
    }
    
    
    
    //MARK: - delegate
    func sessionHandleEvent(session:MQTTSession, eventCode:MQTTSessionEvent) {
        if self.isConnected != (eventCode == .MQTTSessionEventConnected) {
            self.isConnected = (eventCode == .MQTTSessionEventConnected) 
        }
        switch eventCode {
        case .MQTTSessionEventConnected:
            print("connect")
            self.connectType = .MQTTManagerConnectTypeConnect
            sendMQTTMessage("hello world".dataUsingEncoding(NSUTF8StringEncoding))
        case .MQTTSessionEventConnectionRefused:
            print("refrused")
            self.connectType = .MQTTManagerConnectTypeDisconnect
            
            disconnectMQTT()
            
        case .MQTTSessionEventConnectionClosed:
            print("closed")
            if self.mqttClient != nil {
                self.mqttClient.delegate = nil
            }
            self.connectType = .MQTTManagerConnectTypeClose
            
            self.mqttClient = nil
            
        case .MQTTSessionEventConnectionError:
            print("error")
            if self.connectType?.rawValue < 3 {
                self.connectType = .MQTTManagerConnectTypeDisconnect
                print("connection error")
                print("reconnecting...after 5s...")
                weak var weakSelf = self as MqttManager
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, Int64(5 * Double(NSEC_PER_SEC))),dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), { () -> Void in
                    weakSelf?.mqttClient.deallocSession()
                    if weakSelf?.mqttClient != nil && weakSelf?.connectType == .MQTTManagerConnectTypeDisconnect {
                        weakSelf?.connectType = .MQTTManagerConnectTypeIng
                        
                        weakSelf?.mqttClient .connectToHost(MQTT_HOST, port: MQTT_PORT)
                    }
                })
            }
        case .MQTTSessionEventProtocolError:
            print("protocol error")
            self.connectType = .MQTTManagerConnectTypeDisconnect
        }
    }
    func sessionNewMessageOnTopic(session:MQTTSession, data:NSData, topic:String) {
        let queue:dispatch_queue_t = dispatch_queue_create("SaveRecMessageList", nil)
        dispatch_async(queue) { () -> Void in
            print(NSString(data:data, encoding:NSUTF8StringEncoding) )
        }
    }
    
    ///消息发送后状态的回调SendStatus，mid是发送消息体的自己生成的唯一标识，参考sendMQTTMessage方法中的mid
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