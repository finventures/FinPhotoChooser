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
    @IBOutlet weak var triggerButton: UIButton!
    private let pc = ImagePickerViewController()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        pc.delegate = self
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = 5
        imageView.layer.borderWidth = 1
        imageView.layer.borderColor = UIColor.whiteColor().colorWithAlphaComponent(0.5).CGColor
        triggerButton.backgroundColor = UIColor.whiteColor().colorWithAlphaComponent(0.4)
        triggerButton.layer.cornerRadius = 3
        triggerButton.setTitle("🔥🌄📷🔥", forState: .Normal)
    }
    
    @IBAction func showChooser(sender: AnyObject) {
        pc.show(fromVc: self)
    }
    
    func didSelectImage(image: UIImage) {
        imageView.image = image
    }
    
    override func preferredStatusBarStyle() -> UIStatusBarStyle {
        return .LightContent
    }
    
}

