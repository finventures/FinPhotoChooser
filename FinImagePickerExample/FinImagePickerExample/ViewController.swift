//
//  ViewController.swift
//  FinImagePickerExample
//
//  Created by Rob Cheung on 8/22/15.
//  Copyright (c) 2015 Fin Ventures. All rights reserved.
//

import UIKit
import FinPhotoChooser

class ViewController: UIViewController, ImagePickerDelegate {

    @IBOutlet weak var imageView: UIImageView!
    private let pc: ImagePickerView = {
        let screen = UIScreen.mainScreen().bounds
        let v = ImagePickerView(frame: CGRect(x: 0, y: 0, width: screen.width, height: 255))
        return v
    }()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pc.delegate = self
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 5
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.whiteColor().colorWithAlphaComponent(0.5).CGColor
    }
    
    override var inputView: UIView? { return pc }
    
    override func canBecomeFirstResponder() -> Bool {
        return true
    }
    
    func didSelectImage(image: UIImage) {
        imageView.image = image
    }
    
    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return .LightContent
    }
    
}

