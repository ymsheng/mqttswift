//
//  MQTTSession.swift
//  BossSwift
//
//  Created by mosn on 12/31/15.
//  Copyright © 2015 com.hpbr.111. All rights reserved.
//

import Foundation

@objc public enum SendStatus: Int{
    case SendStatusIng = 0
    case SendStatusFinish = 1
    case SendStatusFailed = 2
}

@objc public enum MQTTSessionStatus:Int {
    case MQTTSessionStatusCreated
    case MQTTSessionStatusConnecting
    case MQTTSessionStatusConnected
    case MQTTSessionStatusError
}

@objc public enum MQTTSessionEvent: Int {
    case MQTTSessionEventConnected
    case MQTTSessionEventConnectionRefused
    case MQTTSessionEventConnectionClosed
    case MQTTSessionEventConnectionError
    case MQTTSessionEventProtocolError
}

@objc public protocol MQTTSessionDelegate {
   optional func sessionHandleEvent(session:MQTTSession, eventCode:MQTTSessionEvent)
   optional func sessionNewMessageOnTopic(session:MQTTSession, data:NSData, topic:String)
   optional func sessionCompletionMidWithStatus(session:MQTTSession, mid:Double, status:SendStatus)
   optional func sessionCompletionIndex(session:MQTTSession, index:String)
}

typealias eventBlock = (MQTTSessionEvent) -> Void
typealias messageBlock = (NSData,String) -> Void

@objc public class MQTTSession : NSObject, MQTTDecoderDelegate,MQTTEncoderDelegate {
    var flightFlag:Bool = true ///flight window
    public var delegate:MQTTSessionDelegate?
    var status:MQTTSessionStatus!
    var clientId:String!
    var keepAliveInterval:Int!
    var cleanSessionFlag:Bool!
    var connectMessage:MQTTMessage!
    var runLoop:NSRunLoop!
    var runLoopMode:String!
    var idleTimer:Int = 0
    var txMsgId:Int = 1
    var txFlows:NSMutableDictionary!
    var rxFlows:NSMutableDictionary!
    var ticks:Int = 0
    var outTimer:NSTimer?
    var timer:NSTimer?
    var encoder:MQTTEncoder?
    var decoder:MQTTDecoder?
    var queue:NSMutableArray!
    var timerRing:NSMutableArray!
    var msgMidDict:NSMutableDictionary!
    var msgIndexDict:NSMutableDictionary!
    
    var connectHandler:eventBlock?
    var messageHandler:messageBlock?
    
    public init(theClientId:String, theUserName:String, thePassword:String, theKeepAliveInterval:Int, theCleanSessionFlag:Bool) {
        
        let msg:MQTTMessage = MQTTMessage.connectMessageWithClientId(theClientId, userName: theUserName, password: thePassword, keepAlive: theKeepAliveInterval, cleanSessionFlag: theCleanSessionFlag)
        
        self.connectMessage = msg
        self.clientId = theClientId
        self.keepAliveInterval = theKeepAliveInterval
        self.cleanSessionFlag = theCleanSessionFlag
        self.runLoop = NSRunLoop.currentRunLoop()
        self.runLoopMode = NSRunLoopCommonModes
        self.queue = NSMutableArray()
        self.msgIndexDict = NSMutableDictionary()
        self.msgMidDict = NSMutableDictionary()
        self.txFlows = NSMutableDictionary()
        self.rxFlows = NSMutableDictionary()
        self.timerRing = NSMutableArray(capacity: 60)
        
    }
    
    //MARK: - deinit
    public func deallocSession() {
        if self.timer != nil {
            self.timer?.invalidate()
            self.timer = nil
        }
        if self.txFlows.count > 0 {
            for key in self.txFlows {
                if Int(key.key as! NSNumber) > 0 {
                    if self.msgMidDict.objectForKey(key.key)?.doubleValue > 0 {
                        self.delegate?.sessionCompletionMidWithStatus?(self, mid: (self.msgMidDict.objectForKey(key.key)?.doubleValue)!, status: SendStatus.SendStatusFailed)
                    }
                }
            }
            self.txFlows.removeAllObjects()
        }
        
        self.timerRing.removeAllObjects()
        
        self.msgMidDict.removeAllObjects()
        self.msgIndexDict.removeAllObjects()
        self.queue.removeAllObjects()
        self.encoder?.close()
        self.encoder?.delegate = nil
        self.encoder = nil
        
        self.decoder?.close()
        self.decoder?.delegate = nil
        self.decoder = nil
    }
    
    public func close() {
        self.deallocSession()
        self.error(.MQTTSessionEventConnectionClosed)
    }
    
    
    //MARK: - connect
    public func connectToHost(ip:String, port:Int) {
        for _ in 1...60 {
            self.timerRing.addObject(NSMutableSet())
        }
        
        self.status = MQTTSessionStatus.MQTTSessionStatusCreated
        
        var readStream:NSInputStream?
        var writeStream:NSOutputStream?
        
        NSStream.getStreamsToHostWithName(ip, port: port, inputStream: &readStream, outputStream: &writeStream)
        
        self.encoder = MQTTEncoder.init(stream: writeStream!, runLoop: self.runLoop, mode: self.runLoopMode)
        self.decoder = MQTTDecoder.init(stream: readStream!, runLoop: self.runLoop, mode: self.runLoopMode)
        
        self.encoder?.delegate = self
        self.decoder?.delegate = self
        
        self.encoder?.open()
        self.decoder?.open()
        
        if self.outTimer != nil {
            self.outTimer?.invalidate()
        }
        
        self.outTimer = NSTimer.init(fireDate: NSDate(timeIntervalSinceNow: 30), interval: 1.0, target: self, selector: "disConnectByTimeout", userInfo: nil, repeats: false)
        self.runLoop.addTimer(self.outTimer!, forMode: self.runLoopMode)
    }
    
    @objc private func disConnectByTimeout() {
        error(.MQTTSessionEventConnectionError)
    }
    
    //MARK: - subscritpin
    public func subscribeTopic(theTopic:String, qosLevel:Int) {
        send(MQTTMessage.subscribeMessageWithMessageId(nextMsgId(), topic: theTopic, qos: qosLevel))
    }
    public func unsubscribeTopic(theTopic:String) {
        send(MQTTMessage.unsubscribeMessageWithMessageId(nextMsgId(), topic: theTopic))
    }
    
    public func publishDataExactlyOnce(data:NSData, topic:String, retainFlag:Bool, mid:Double = 0, indexStr:String = "") {
        
        if self.encoder == nil || self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusEndEncountered ||
            self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusError ||
            self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusInitializing {
                self.delegate?.sessionCompletionMidWithStatus?(self, mid: mid, status: .SendStatusFailed)
                return
        }
        
        let msgId = nextMsgId()
        var msg:MQTTMessage = MQTTMessage.publicMessageWithData(data, topic: topic, qosLevel:2, msgId: msgId, retainFlag: retainFlag, dup: false)
        if mid > 0 {
            self.msgMidDict.setObject(NSNumber(double: mid), forKey: NSNumber(long: msgId))
        }
        else if indexStr.characters.count > 0 {
            self.msgIndexDict.setObject(NSNumber(double:Double(indexStr)!), forKey: NSNumber(long: msgId))
        }
        
        let flow:MQTTTxFlow = MQTTTxFlow.flowWithMsgDeadline(msg, aDeadline: (self.ticks+60))
        self.txFlows.setObject(flow, forKey: NSNumber(long:msgId))
        
        let index = flow.deadline % 60
        
        if self.timerRing.count > index {
            self.timerRing.objectAtIndex(index).addObject(NSNumber(double: mid))
        }
        
        if self.queue.count > 0 {
            self.queue.addObject(msg)
            
            msg = self.queue.objectAtIndex(0) as! MQTTMessage
            self.queue.removeObjectAtIndex(0)
        }
        
        sendQueueMsg(msg)
    }
    
    //MARK: - send
    func send(msg:MQTTMessage) {
        
        var sendNow:Bool = false
        if msg.type != MQTTMessageType.MQTTPublish.rawValue || self.flightFlag {
            sendNow = true
        }
        
        if msg.type == MQTTMessageType.MQTTPublish.rawValue {
            self.flightFlag = false
        }
        
        if self.encoder != nil && self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusReady && sendNow {
            self.encoder?.encodeMessage(msg)
        }
        else{
            self.queue.insertObject(msg, atIndex: 0)
        }
        
    }
    
    func sendQueueMsg(msg:MQTTMessage) {
        var sendNow:Bool = false
        if msg.type != MQTTMessageType.MQTTPublish.rawValue || self.flightFlag {
            sendNow = true
        }
        
        if msg.type == MQTTMessageType.MQTTPublish.rawValue {
            self.flightFlag = false
        }
        
        if self.encoder != nil && self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusReady && sendNow {
            self.encoder?.encodeMessage(msg)
        }
        else{
            if self.encoder == nil || self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusEndEncountered || self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusError {
                if checkSendStatus(msg) {
                    self.queue.removeObject(msg)
                }
            }
            else{
                self.queue.insertObject(msg, atIndex: 0)
            }
        }
        
    }
    
    func checkSendStatus(msg:MQTTMessage) -> Bool {
        
        var result:String = NSString(data: msg.data!, encoding: NSUTF8StringEncoding) as! String
        if result.isEmpty == false && result.lengthOfBytesUsingEncoding(NSUTF8StringEncoding) > 2 {
            result = result.stringByReplacingOccurrencesOfString("<", withString: "")
            result = result.stringByReplacingOccurrencesOfString(">", withString: "")
            result = result.stringByReplacingOccurrencesOfString(" ", withString: "")
            
            let mid:Double = Double(strtoul(result.cStringUsingEncoding(NSUTF8StringEncoding)!,UnsafeMutablePointer<UnsafeMutablePointer<Int8>>.alloc(0), 16))
            if mid > 0 {
                if self.msgMidDict.objectForKey(NSNumber(double: mid)) as! Double > 0 {
                    if self.delegate != nil {
                        self.delegate?.sessionCompletionMidWithStatus?(self, mid: mid, status: .SendStatusFailed)
                        return true
                    }
                }
            }
        }
        
        return false
    }
    
    //MARK: - message
    func nextMsgId() -> Int {
        self.txMsgId++;
        repeat {
            self.txMsgId++
        }while(self.txMsgId==0 || self.txFlows.objectForKey(self.txMsgId as NSNumber) != nil )
        
        return self.txMsgId
    }
    
    //MARK: - event
    func error(eventCode:MQTTSessionEvent) {
        
        self.encoder?.close()
        self.encoder?.delegate = nil;
        self.encoder = nil
        
        self.decoder?.close()
        self.decoder?.delegate = nil
        self.decoder = nil
        
        if self.timer != nil {
            self.timer!.invalidate()
            self.timer = nil
        }
        
        if self.outTimer != nil {
            self.outTimer!.invalidate()
            self.outTimer = nil
        }
        
        self.status = .MQTTSessionStatusError
        
        usleep(500000)
        
        if self.delegate != nil {
            self.delegate?.sessionHandleEvent?(self, eventCode: eventCode)
        }
        
        if let exsitBlock = self.connectHandler {
            exsitBlock(eventCode)
        }
    }
    
    func newMessage(msg:MQTTMessage) {
        switch msg.type {
        case MQTTMessageType.MQTTPublish.rawValue:
            handlePublish(msg)
        case MQTTMessageType.MQTTPuback.rawValue:
            handlePuback(msg)
        case MQTTMessageType.MQTTPubrec.rawValue:
            handlePubrec(msg)
        case MQTTMessageType.MQTTPubrel.rawValue:
            handlePubrel(msg)
        case MQTTMessageType.MQTTPubcomp.rawValue:
            handlePubcomp(msg)
        default:
            break
        }
    }
    
    //MARK: hand action
    func handlePublish(msg:MQTTMessage) {
        var data:NSData = msg.data!
        if  data.length < 2 {
            return
        }
        var i = [UInt8](count: 2, repeatedValue: 0)
        data.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let topicLength:Int = 256*high+low
        if data.length < 2+topicLength {
            return
        }
        
        let topicData:NSData = data.subdataWithRange(NSMakeRange(2, topicLength))
        let topic:String = NSString(data: topicData, encoding: NSUTF8StringEncoding) as! String
        let range:NSRange = NSMakeRange(2+topicLength, data.length-topicLength-2)
        data = data.subdataWithRange(range)
        
        if msg.qos == 0 {
            if self.delegate != nil {
                self.delegate?.sessionNewMessageOnTopic?(self, data:data, topic: topic)
            }
            if self.messageHandler != nil {
                self.messageHandler!(data,topic)
            }
        }
        else {
            if data.length < 2 {
                return
            }
            
            var i = [UInt8](count: 2, repeatedValue: 0)
            data.getBytes(&i, length: 2)
            let high = Int(i[0])
            let low = Int(i[1])
            let msgId:Int = 256*high+low
            if msgId == 0 {
                return
            }
            data = data.subdataWithRange(NSMakeRange(2, data.length-2))
            if msg.qos == 1 {
                if self.delegate != nil {
                    self.delegate?.sessionNewMessageOnTopic?(self, data: data, topic: topic)
                }
                if self.messageHandler != nil {
                    self.messageHandler!(data,topic)
                }
                send(MQTTMessage.pubackMessageWithMessageId(msgId))
            }
            else{
                let dict:NSDictionary = NSDictionary(objects: [data,topic], forKeys: ["data","topic"])
                self.rxFlows.setObject(dict, forKey: NSNumber(long: msgId))
                
                send(MQTTMessage.pubrecMessageWithMessageId(msgId))
            }
            
        }
    }
    
    func handlePuback(msg:MQTTMessage) {
        if msg.data == nil || msg.data?.length != 2 {
            return
        }
        var i = [UInt8](count: 2, repeatedValue: 0)
        msg.data!.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let msgId:Int = 256*high+low
        if msgId == 0 {
            return
        }
        
        if let flow:MQTTTxFlow = self.txFlows.objectForKey(NSNumber(long: msgId)) as? MQTTTxFlow {
            if flow.msg?.type != MQTTMessageType.MQTTPublish.rawValue || flow.msg?.qos != 1 {
                return
            }
            
            let rIndex:Int = flow.deadline % 60
            if self.timerRing != nil && self.timerRing.count > rIndex {
                (self.timerRing.objectAtIndex(rIndex) as! NSMutableSet).removeObject(NSNumber(long: msgId))
            }
            
            self.txFlows.removeObjectForKey(NSNumber(long: msgId))
        }
    }
    
    func handlePubrec(msg:MQTTMessage) {
        if msg.data == nil || msg.data?.length != 2 {
            return
        }
        
        var i = [UInt8](count: 2, repeatedValue: 0)
        msg.data!.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let msgId:Int = 256*high+low
        if msgId == 0 {
            return
        }
        if let flow:MQTTTxFlow = self.txFlows.objectForKey(NSNumber(long: msgId)) as? MQTTTxFlow {
            if flow.msg?.type != MQTTMessageType.MQTTPublish.rawValue || flow.msg?.qos != 2 {
                return
            }
            
            let msg:MQTTMessage = MQTTMessage.pubrelMessageWithMessageId(msgId)
            flow.msg = msg
            
            var rIndex:Int = flow.deadline % 60
            if self.timerRing != nil && self.timerRing.count > rIndex {
                (self.timerRing.objectAtIndex(rIndex) as! NSMutableSet).removeObject(NSNumber(long: msgId))
            }
            
            flow.deadline = ticks + 60
            rIndex = flow.deadline % 60
            if self.timerRing != nil && self.timerRing.count > rIndex {
                (self.timerRing.objectAtIndex(rIndex) as! NSMutableSet).addObject(NSNumber(long: msgId))
            }
            
            send(msg)
        }
        
    }
    
    func handlePubrel(msg:MQTTMessage) {
        if msg.data == nil || msg.data?.length != 2 {
            return
        }
        
        var i = [UInt8](count: 2, repeatedValue: 0)
        msg.data!.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let msgId:Int = 256*high+low

        if msgId == 0 {
            return
        }
        
        if let dict:NSDictionary = self.rxFlows.objectForKey(NSNumber(long: msgId)) as? NSDictionary {
            if self.delegate != nil {
                self.delegate?.sessionNewMessageOnTopic?(self, data: dict.objectForKey("data") as! NSData, topic: dict.objectForKey("topic") as! String)
            }
            if self.messageHandler != nil {
                self.messageHandler!(dict.objectForKey("data") as! NSData,dict.objectForKey("topic") as! String)
            }
            
            self.rxFlows.removeObjectForKey(NSNumber(long: msgId))
        }
        
        send(MQTTMessage.pubcompMessageWithMessageId(msgId))
    }
    
    func handlePubcomp(msg:MQTTMessage) {
        if msg.data == nil || msg.data?.length != 2 {
            return
        }
        
        var i = [UInt8](count: 2, repeatedValue: 0)
        msg.data!.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let msgId:Int = 256*high+low

        if msgId == 0 {
            return
        }
        
        if let flow:MQTTTxFlow = self.txFlows.objectForKey(NSNumber(long: msgId)) as? MQTTTxFlow {
            if flow.msg?.type != MQTTMessageType.MQTTPubrel.rawValue {
                return
            }
            
            let rIndex:Int = flow.deadline % 60
            if self.timerRing != nil && self.timerRing.count > rIndex {
                (self.timerRing.objectAtIndex(rIndex) as! NSMutableSet).removeObject(NSNumber(long: msgId))
            }
            
            self.txFlows.removeObjectForKey(NSNumber(long: msgId))
            
            pubcomFinish(msg)
        }
    }
    
    
    func pubcomFinish(msg:MQTTMessage){
        var i = [UInt8](count: 2, repeatedValue: 0)
        msg.data!.getBytes(&i, length: 2)
        let high = Int(i[0])
        let low = Int(i[1])
        let mid:Int = 256*high+low
        
        
        if mid > 0 {
            let sendMsgId = self.msgMidDict.objectForKey(NSNumber(long: mid)) as? Double
            let sendIndexId = self.msgIndexDict.objectForKey(NSNumber(long: mid)) as? Double
            if sendMsgId > 0 {
                if self.delegate != nil {
                    self.delegate?.sessionCompletionMidWithStatus?(self, mid: sendMsgId!, status: .SendStatusFinish)
                }
            }
            else if sendIndexId > 0 {
                if self.delegate != nil {
                    self.delegate?.sessionCompletionIndex?(self, index: "\(sendIndexId)")
                }
            }
            
            self.msgMidDict.removeObjectForKey(NSNumber(long: mid))
        }
        
        
        self.flightFlag = true
        if self.queue.count > 0 {
            let msg:MQTTMessage = self.queue.objectAtIndex(0) as! MQTTMessage
            self.queue.removeObjectAtIndex(0)
            sendQueueMsg(msg)
        }
    }
    
    //MARK: - decode delegate
    func decoderNewMessage(sender:MQTTDecoder, msg:MQTTMessage) {
        if sender == self.decoder {
            switch self.status! {
            case .MQTTSessionStatusConnecting:
                if  msg.type == MQTTMessageType.MQTTConnack.rawValue {
                    if msg.data?.length != 2 {
                        error(.MQTTSessionEventProtocolError)
                    }
                    else{
                        var i = [UInt8](count:2, repeatedValue: 0)
                        msg.data?.getBytes(&i, length: 2)
                        
                        let byte1:Int = Int(i[1])
                        
                        if byte1  == 0 {
                            self.status = MQTTSessionStatus.MQTTSessionStatusConnected
                            if self.timer != nil {
                                self.timer?.invalidate()
                                self.timer = nil
                            }
                            
                            self.timer = NSTimer(fireDate: NSDate(timeIntervalSinceNow: 1), interval: 1.0, target: self, selector: "timerHandler", userInfo: nil, repeats: true)
                            if self.connectHandler != nil {
                                self.connectHandler!(.MQTTSessionEventConnected)
                            }
                            self.flightFlag = true
                            if self.delegate != nil {
                                self.delegate?.sessionHandleEvent?(self, eventCode: .MQTTSessionEventConnected)
                            }
                            
                            self.runLoop.addTimer(self.timer!, forMode: self.runLoopMode)
                        }
                        else{
                            error(.MQTTSessionEventConnectionRefused)
                        }
                    }
                }
                else{
                    error(.MQTTSessionEventProtocolError)
                }
                
            case MQTTSessionStatus.MQTTSessionStatusConnected:
                newMessage(msg)
                
            default:break
            }
        }
    }
    
    @objc private func timerHandler() {
        self.idleTimer++
        if self.idleTimer >= self.keepAliveInterval {
            if self.encoder?.status == MQTTEncoderStatus.MQTTEncoderStatusReady {
                self.encoder?.encodeMessage(MQTTMessage.pingreqMessage())
            }
        }
        self.ticks++
        if self.timerRing != nil && self.timerRing.count > (self.ticks % 60) {
            let e:NSEnumerator = self.timerRing.objectAtIndex(self.ticks % 60).objectEnumerator()
            
            for msgId in e.allObjects {
                let flow:MQTTTxFlow? = self.txFlows.objectForKey(msgId) as? MQTTTxFlow
                if flow != nil {
                    if let msg:MQTTMessage = flow!.msg {
                        flow!.deadline = self.ticks+60
                        msg.setDupFlag()
                        send(msg)
                    }
                    
                }
            }
            
        }
    }
    
    func decodeHandleEvent(sender:MQTTDecoder, eventCode:MQTTDecoderEvent) {
        if self.outTimer != nil {
            self.outTimer?.invalidate()
            self.outTimer = nil
        }
        
        if sender == self.decoder {
            var event:MQTTSessionEvent!
            switch eventCode {
            case .MQTTDecoderEventConnectionClosed:
                event = MQTTSessionEvent.MQTTSessionEventConnectionClosed
            case .MQTTDecoderEventConnectionError:
                event = MQTTSessionEvent.MQTTSessionEventConnectionError
            case .MQTTDecoderEventProtocolError:
                event = MQTTSessionEvent.MQTTSessionEventProtocolError
            }
            
            error(event)
        }
    }
    
    //MARK: - encode delegate
    func encoderHandleEvent(sender:MQTTEncoder, eventCode:MQTTEncoderEvent) {
        if self.outTimer != nil {
            self.outTimer?.invalidate()
            self.outTimer = nil
        }
        
        if sender == self.encoder {
            switch eventCode {
            case .MQTTEncoderEventReady:
                
                switch self.status! {
                case .MQTTSessionStatusCreated:
                    sender.encodeMessage(self.connectMessage)
                    self.status = MQTTSessionStatus.MQTTSessionStatusConnecting
                case .MQTTSessionStatusConnected:
                    if self.queue.count > 0 {
                        let msg:MQTTMessage = self.queue.objectAtIndex(0) as! MQTTMessage
                        self.queue.removeObjectAtIndex(0)
                        sendQueueMsg(msg)
                    }
                default:break
                }
                
            case .MQTTEncoderEventErrorOccurred:
                error(.MQTTSessionEventConnectionError)
            }
        }
        
        
        
        
    }
}