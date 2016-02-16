//
//  MQTTTxFlow.swift
//  BossSwift
//
//  Created by mosn on 12/31/15.
//  Copyright © 2015 com.hpbr.111. All rights reserved.
//

import Foundation

class MQTTTxFlow {
    var msg:MQTTMessage?
    var deadline:Int
    
    class func flowWithMsgDeadline(aMsg:MQTTMessage, aDeadline:Int) -> MQTTTxFlow {
        return MQTTTxFlow.init(aMsg: aMsg, aDeadline: aDeadline)
    }
    
    init(aMsg:MQTTMessage, aDeadline:Int) {
        self.msg = aMsg
        self.deadline = aDeadline
    }
}