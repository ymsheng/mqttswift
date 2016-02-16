//
//  MQTTDecode.swift
//  BossSwift
//
//  Created by mosn on 12/31/15.
//  Copyright © 2015 com.hpbr.111. All rights reserved.
//

import Foundation

public enum MQTTDecoderEvent {
    case MQTTDecoderEventProtocolError
    case MQTTDecoderEventConnectionClosed
    case MQTTDecoderEventConnectionError
}

public enum MQTTDecoderStatus {
    case MQTTDecoderStatusInitializing
    case MQTTDecoderStatusDecodingHeader
    case MQTTDecoderStatusDecodingLength
    case MQTTDecoderStatusDecodingData
    case MQTTDecoderStatusConnectionClosed
    case MQTTDecoderStatusConnectionError
    case MQTTDecoderStatusProtocolError
}

protocol MQTTDecoderDelegate {
    func decoderNewMessage(sender:MQTTDecoder, msg:MQTTMessage)
    func decodeHandleEvent(sender:MQTTDecoder, eventCode:MQTTDecoderEvent)
}

class MQTTDecoder: NSObject, NSStreamDelegate {
    
    var status:MQTTDecoderStatus
    var stream:NSInputStream?
    var runLoop:NSRunLoop
    var runLoopMode:String
    
    var header:UInt8
    var length:Int
    var lengthMultiplier:Int
    var dataBuffer:NSMutableData?
    var delegate:MQTTDecoderDelegate?
    
    init(stream:NSInputStream, runLoop:NSRunLoop, mode:String) {
        
        self.status = .MQTTDecoderStatusInitializing
        self.stream = stream
        self.runLoop = runLoop
        self.runLoopMode = mode
        
        self.header = 0
        self.length = 0
        self.lengthMultiplier = 0
    }
    
    func open() {
        self.stream?.delegate = self
        self.stream?.scheduleInRunLoop(self.runLoop, forMode: self.runLoopMode)
        self.stream?.open()
    }
    
    func close() {
        self.stream?.close()
        self.stream?.removeFromRunLoop(self.runLoop, forMode: self.runLoopMode)
        self.stream?.delegate = nil
    }
    
    internal func stream(aStream: NSStream, handleEvent eventCode: NSStreamEvent) {
        if self.stream == nil || aStream != self.stream {
            return
        }
        
        switch eventCode {
        case NSStreamEvent.OpenCompleted:
            self.status = .MQTTDecoderStatusDecodingHeader
        case NSStreamEvent.HasBytesAvailable:
            if self.status == .MQTTDecoderStatusDecodingHeader {
                var buffer:UInt8 = 0
                var readByte = [UInt8](count: 1, repeatedValue: 0)
                let n:Int? = self.stream?.read(&readByte, maxLength: 1)
                buffer = readByte[0]
                self.header = buffer
                if n == -1 {
                    self.status = .MQTTDecoderStatusConnectionError
                    self.delegate?.decodeHandleEvent(self, eventCode: .MQTTDecoderEventConnectionError)
                    return
                }
                else if n == 1 {
                    self.length = 0
                    self.lengthMultiplier = 1
                    self.status = .MQTTDecoderStatusDecodingLength
                }
            }
            
            repeat {
                
                var digit:UInt8 = 0
                var readByte = [UInt8](count: 1, repeatedValue: 0)
                let n:Int? = self.stream?.read(&readByte, maxLength: 1)
                digit = readByte[0]
                
                if n == -1 {
                    self.status = .MQTTDecoderStatusProtocolError
                    self.delegate?.decodeHandleEvent(self, eventCode: .MQTTDecoderEventConnectionError)
                    break
                } else if n==0 {
                    break
                }

                let digitNum = Int(digit & 0x7f)
                
                self.length += digitNum * self.lengthMultiplier
                if (digit & 0x80) == 0x00 {
                    self.dataBuffer = NSMutableData.init(capacity: self.length)
                    self.status = .MQTTDecoderStatusDecodingData
                }
                else {
                    self.lengthMultiplier *= 128
                    if self.lengthMultiplier > 128*128 {
                        break
                    }
                }
            } while (self.delegate != nil && self.status == .MQTTDecoderStatusDecodingLength)
            
            if self.status == .MQTTDecoderStatusDecodingData {
                if self.length > 0 {
                    var n:Int = 0
                    var toRead:Int = 0
                   
                    if self.dataBuffer != nil {
                        toRead = self.length - self.dataBuffer!.length
                    }
                    else{
                        toRead = self.length
                    }
                 
                     var buffer = [UInt8](count: toRead, repeatedValue: 0)
                    
                    n = (self.stream?.read(&buffer, maxLength: toRead))!
                    if n == -1 {
                        self.status = .MQTTDecoderStatusConnectionError
                        self.delegate?.decodeHandleEvent(self, eventCode: .MQTTDecoderEventConnectionError)
                        return
                    }
                    else {
                        self.dataBuffer?.appendBytes(&buffer, length: n)
                    }
                }
              
                if self.dataBuffer?.length == self.length {

                    let type:UInt8 = (self.header >> 4) & 0x0f
                    let qos:UInt8 = (self.header >> 1) & 0x03
                    var isDuplicate:Bool = false
                    var retainFlag:Bool = false
                    if (self.header & 0x08) == 0x08 {
                        isDuplicate = true
                    }
                    if (self.header & 0x01) == 0x01 {
                        retainFlag = true
                    }
                    
                    let msg:MQTTMessage = MQTTMessage.init(aType: type, aQos: qos, aRetainFlag: retainFlag, aDupFlag: isDuplicate, aData: self.dataBuffer!)
                    
                    
                    self.status = .MQTTDecoderStatusDecodingHeader
                    if self.delegate != nil {
                        self.delegate?.decoderNewMessage(self, msg: msg)
                    }
                    
                }
            }
            
        case NSStreamEvent.EndEncountered:
            self.status = .MQTTDecoderStatusConnectionError
            self.delegate?.decodeHandleEvent(self, eventCode: .MQTTDecoderEventConnectionError)
        case NSStreamEvent.ErrorOccurred:
            self.status = .MQTTDecoderStatusProtocolError
            self.delegate?.decodeHandleEvent(self, eventCode: .MQTTDecoderEventConnectionError)
        default:break
        }
    }
    
    deinit {
        
    }
}