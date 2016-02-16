//
//  MQTTEncoder.swift
//  BossSwift
//
//  Created by mosn on 12/31/15.
//  Copyright © 2015 com.hpbr.111. All rights reserved.
//

import Foundation

public enum MQTTEncoderEvent {
    case MQTTEncoderEventReady
    case MQTTEncoderEventErrorOccurred
}

public enum MQTTEncoderStatus {
    case MQTTEncoderStatusInitializing
    case MQTTEncoderStatusReady
    case MQTTEncoderStatusSending
    case MQTTEncoderStatusEndEncountered
    case MQTTEncoderStatusError
}

protocol MQTTEncoderDelegate {
    func encoderHandleEvent(sender:MQTTEncoder, eventCode:MQTTEncoderEvent)
}

class MQTTEncoder : NSObject,NSStreamDelegate{
    var status:MQTTEncoderStatus
    var stream:NSOutputStream?
    var runLoop:NSRunLoop
    var runLoopMode:String
    var buffer:NSMutableData?
    var byteIndex:Int
    var delegate:MQTTEncoderDelegate?
    
    init(stream:NSOutputStream, runLoop:NSRunLoop, mode:String) {
        self.status = .MQTTEncoderStatusInitializing
        self.stream = stream
        self.runLoop = runLoop
        self.runLoopMode = mode
        self.byteIndex = 0
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
            break
        case NSStreamEvent.HasSpaceAvailable:
            if self.status == .MQTTEncoderStatusInitializing {
                self.status = .MQTTEncoderStatusReady
                self.delegate?.encoderHandleEvent(self, eventCode: .MQTTEncoderEventReady)
            }
            else if self.status == .MQTTEncoderStatusReady {
                self.delegate?.encoderHandleEvent(self, eventCode: .MQTTEncoderEventReady)
            }
            else if self.status == .MQTTEncoderStatusSending {
                //
                var ptr:UnsafePointer<Void>
                var n:Int = 0
                var length:Int = 0
                ptr = self.buffer!.bytes.advancedBy(self.byteIndex)
                
                length = self.buffer!.length - self.byteIndex
                n = self.stream!.write(UnsafePointer<UInt8>(ptr), maxLength: length)
                if n == -1 {
                    self.status = .MQTTEncoderStatusError
                    self.delegate?.encoderHandleEvent(self, eventCode: .MQTTEncoderEventErrorOccurred)
                }
                else if n < length {
                    self.byteIndex += n
                }
                else {
                    self.buffer = nil
                    self.byteIndex = 0
                    self.status = .MQTTEncoderStatusReady
                }
            }
            
        case NSStreamEvent.EndEncountered, NSStreamEvent.ErrorOccurred:
            if self.status != .MQTTEncoderStatusError {
                self.status = .MQTTEncoderStatusError
                self.delegate?.encoderHandleEvent(self, eventCode: .MQTTEncoderEventErrorOccurred)
            }
        default:break
        }
    }
    
    func encodeMessage(msg:MQTTMessage) {
        var header:UInt8 = 0
        var n:Int = 0
        var length:Int = 0
        
        if self.status != .MQTTEncoderStatusReady || self.stream == nil || self.stream?.streamStatus != NSStreamStatus.Open {
            return
        }
        
        if self.buffer != nil {
            return
        }
        if self.byteIndex != 0 {
            return
        }
        
        self.buffer = NSMutableData()
        
        header = (msg.type & 0x0f) << 4
        if msg.isDuplicate {
            header |= 0x08
        }
        header |= (msg.qos & 0x03) << 1
        if msg.retainFlag {
            header |= 0x01
        }
        
        self.buffer?.appendBytes(&header, length: 1)
        
        if let data = msg.data {
            length = data.length
        }
        
        repeat {
            var digit:Int = length % 128
            length /= 128
        if length > 0 {
            digit |= 0x08
            }
            self.buffer?.appendBytes(&digit, length: 1)
        } while (length > 0)
        
        if let data = msg.data {
            self.buffer?.appendData(data)
        }
        
        if self.stream!.hasSpaceAvailable {
            n = self.stream!.write(UnsafePointer<UInt8>(self.buffer!.bytes), maxLength: self.buffer!.length)
        }
        
        if n == -1 {
            self.status = .MQTTEncoderStatusError
            self.delegate?.encoderHandleEvent(self, eventCode: .MQTTEncoderEventErrorOccurred)
        }
        else if n < self.buffer?.length {
            self.byteIndex += n
            self.status = .MQTTEncoderStatusSending
        }
        else {
            self.buffer = nil
        }
        
    }
    
}