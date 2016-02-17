# MqttSwift
mqtt by swift.
MQTT（Message Queuing Telemetry Transport，消息队列遥测传输）是IBM开发的一个即时通讯协议.
我们在开发聊天的时间可以通过实现此协议完成相关功能。相对其他swift版本，MqttSwift增加了消息发送是否成功的回调方法，并且聊天窗口个数是1.以下给出了调用的单例模式。
##使用说明：
1.参考MqttManager.swift
let MQTT_PORT:Int = 2345  //chat server port 聊天服务器的端口
let MQTT_HOST:String = "192.168.1.166"// "your chat ip" 聊天服务器的地址
self.mqttClient = MQTTSession(theClientId: "your clinetId", theUserName:"user name", thePassword:"user password", theKeepAliveInterval: 40, theCleanSessionFlag: true) //心跳包40s发一次

2.把用户名和密码设置后，调用 MqttManager.sharedInstance.connectMQTT() 即可进行连接服务器，包括了设置用户名和密码

3.应用进入后时，调用 MqttManager.sharedInstance.disconnectMQTT() 断开连接

4.应用从后台唤醒时，调用 MqttManager.sharedInstance.connectToHost() 进行重连接

5.订阅聊天话题，调用 MqttManager.sharedInstance.subscribe("your topic name")

6.发送消息，调用 MqttManager.sharedInstance.sendMQTTMessage("your content data") 把发送的内容转换成NSData

7.连接状态的回调方法，public func sessionHandleEvent(session:MQTTSession, eventCode:MQTTSessionEvent)，在些方法中可以判断连接成功，失败，断开等状态；已实现断开5s后重连接

8.接收到服务器消息的回调方法， public func sessionNewMessageOnTopic(session:MQTTSession, data:NSData, topic:String) ，收到消息后的处理

9.自己发送的消息是否成功的回调方法， public func sessionCompletionMidWithStatus(session:MQTTSession, mid:Double, status:SendStatus) 此方法返回发送的消息是否成功到达服务器。返回的mid的与sendMQTTMessage中的mid相同

##安装说明：
###1.直接下载源码，把MNMqttSwift中的5个文件添加到工程中，参考MqttManager.swift中的实现进行连接测试。
###2.CocoaPods安装
 1.在Podfile 中添加:
     platform :ios, "8.0"
     use_frameworks!
     pod 'MqttSwift', '~> 0.0.3'

 2.执行 pod install 或 pod update

 3.在使用类中 import MqttSwift

了解CocoaPods

http://ymsheng.github.io/cocoapods.html


