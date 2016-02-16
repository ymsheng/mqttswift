//
//  MQTTMessage.swift
//  BossSwift
//
//  Created by mosn on 12/31/15.
//  Copyright © 2015 com.hpbr.111. All rights reserved.
//

import Foundation

public enum MQTTMessageType:UInt8 {
    case MQTTConnect = 1
    case MQTTConnack = 2
    case MQTTPublish = 3
    case MQTTPuback = 4
    case MQTTPubrec = 5
    case MQTTPubrel = 6
    case MQTTPubcomp = 7
    case MQTTSubscribe = 8
    case MQTTSuback = 9
    case MQTTUnsubscribe = 10
    case MQTTUnsuback = 11
    case MQTTPingreq = 12
    case MQTTPingresp = 13
    case MQTTDisconnect = 14
}

class MQTTMessage : NSObject {

    var type:UInt8 = 0
    var qos:UInt8 = 0
    var retainFlag:Bool = false
    var isDuplicate:Bool = false
    var data:NSData?
    
    
    //MARK: - init
    init(aType:UInt8) {
        self.type = aType
        self.data = nil
    }
    
    init(aType:UInt8, aData:NSData) {
        self.type = aType
        self.data = aData
    }
    
    init(aType:UInt8, aQos:UInt8, aData:NSData) {
        self.type = aType
        self.qos = aQos
        self.data = aData
    }
    
    init(aType:UInt8, aQos:UInt8, aRetainFlag:Bool, aDupFlag:Bool, aData:NSData) {
        self.type = aType
        self.qos = aQos
        self.retainFlag = aRetainFlag
        self.isDuplicate = aDupFlag
        self.data = aData
    }
    
    
    class func connectMessageWithClientId(clientId:String, userName:String, password:String, keepAlive:Int, cleanSessionFlag:Bool) -> MQTTMessage {
        var msg:MQTTMessage!
        var flags:UInt8 = 0x00
        if cleanSessionFlag {
            flags |= 0x02
        }
        if userName.isEmpty == false {
            flags |= 0x80
            if password.isEmpty == false {
                flags |= 0x40
            }
        }
        
        let data:NSMutableData = NSMutableData()
        data.appendMQTTString("MQTT")
        data.appendByte(4)
        data.appendByte(Int(flags))
        data.appendUInt16BigEndian(keepAlive)
        data.appendMQTTString(clientId)
        if userName.isEmpty == false {
            data.appendMQTTString(userName)
            if password.isEmpty == false {
                data.appendMQTTString(password)
            }
        }
        msg = MQTTMessage.init(aType: MQTTMessageType.MQTTConnect.rawValue, aData: data)
        
        return msg
    }
    
    class func connectMessageWithClientId(clientId:String, userName:String, password:String, keepAlive:Int, cleanSessionFlag:Bool, willTopic:String, willMsg:NSData, willQos:UInt8, willRetainFlag:Bool) -> MQTTMessage {
        var flags:UInt8 = 0x04 | (willQos<<4 & 0x18)
        if willRetainFlag {
            flags |= 0x20
        }
        if cleanSessionFlag {
            flags |= 0x20
        }
        if userName.isEmpty == false {
            flags |= 0x80
            if password.isEmpty == false {
                flags |= 0x40
            }
        }
        
        let data:NSMutableData = NSMutableData()
        data.appendMQTTString("MQTT")
        data.appendByte(4)
        data.appendByte(Int(flags))
        data.appendUInt16BigEndian(keepAlive)
        data.appendMQTTString(clientId)
        data.appendMQTTString(willTopic)
        data.appendUInt16BigEndian(willMsg.length)
        data.appendData(willMsg)
        if userName.isEmpty == false {
            data.appendMQTTString(userName)
            if password.isEmpty == false {
                data.appendMQTTString(password)
            }
        }
        
        let msg = MQTTMessage.init(aType: MQTTMessageType.MQTTConnect.rawValue, aData: data)
        
        return msg
    }
    
    //MARK: - func
    class func pingreqMessage() -> MQTTMessage {
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPingreq.rawValue)
    }
    
    class func subscribeMessageWithMessageId(msgId:Int, topic:String, qos:Int) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        data.appendMQTTString("MQTT")
        data.appendByte(qos)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTSubscribe.rawValue, aQos: 1, aData: data)
        
    }
    
    class func unsubscribeMessageWithMessageId(msgId:Int, topic:String) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        data.appendMQTTString(topic)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTUnsubscribe.rawValue, aQos: 1, aData: data)
    }
    
    class func publishMessageWithData(payload:NSData, theTopic:String, retainFlag:Bool) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendMQTTString(theTopic)
        data.appendData(payload)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPublish.rawValue, aQos: 0, aRetainFlag: retainFlag, aDupFlag: false, aData: data)
    }
    
    class func publicMessageWithData(payload:NSData, topic:String, qosLevel:UInt8, msgId:Int, retainFlag:Bool, dup:Bool) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendMQTTString(topic)
        data.appendUInt16BigEndian(msgId)
        data.appendData(payload)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPublish.rawValue, aQos: qosLevel, aRetainFlag: retainFlag, aDupFlag: dup, aData: data)
    }
    
    class func pubackMessageWithMessageId(msgId:Int) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPuback.rawValue, aData: data)
    }
    
    class func pubrecMessageWithMessageId(msgId:Int) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPubrec.rawValue, aData: data)
    }
    
    class func pubrelMessageWithMessageId(msgId:Int) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPubrel.rawValue, aData: data)
    }
    
    class func pubcompMessageWithMessageId(msgId:Int) -> MQTTMessage {
        let data:NSMutableData = NSMutableData()
        data.appendUInt16BigEndian(msgId)
        
        return MQTTMessage.init(aType: MQTTMessageType.MQTTPubcomp.rawValue, aData: data)
    }
    
    
    //MARK: - func
    func setDupFlag() {
        self.isDuplicate = true
    }
    
}

extension NSMutableData {
    func appendByte(byte:Int) {
        var val = byte
        self.appendBytes(&val, length: 1)
    }
    
    func appendUInt16BigEndian(val:Int) {
        self.appendByte(val/256)
        self.appendByte(val%256)
    }
    
    func appendMQTTString(string:String) {
        var buf = [Int](count: 2, repeatedValue: 0)
        let strLen = string.lengthOfBytesUsingEncoding(NSUTF8StringEncoding)
        buf[0] = strLen/256
        buf[1] = strLen%256
        self.appendUInt16BigEndian(strLen)
//        self.appendBytes(&buf, length: 2)
        self.appendBytes(string.cStringUsingEncoding(NSUTF8StringEncoding)!, length: strLen)
    }
    
    
}