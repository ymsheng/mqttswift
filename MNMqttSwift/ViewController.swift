//
//  ViewController.swift
//  MNMqttSwift
//
//  Created by mosn on 2/15/16.
//  Copyright © 2016 com.*. All rights reserved.
//

import UIKit

class ViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        
        MqttManager.sharedInstance.connectMQTT()
        // Do any additional setup after loading the view, typically from a nib.
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }


}

