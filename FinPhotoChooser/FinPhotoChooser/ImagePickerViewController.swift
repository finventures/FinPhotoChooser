//
//  ImagePickerViewController.swift
//  Fin
//
//  Created by Robert Cheung on 8/14/15.
//  Copyright (c) 2015 Fin. All rights reserved.
//

import UIKit
import Photos
import AVFoundation

protocol ImagePickerDelegate {
    func didSelectImage(image: UIImage)
}

class ImagePickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    
    private static let screenSize = UIScreen.mainScreen().bounds.size
    private static let pickerHeight: CGFloat = 280
    private static let expectedCellWidth: CGFloat = 240
    private static let targetSize = CGSize(width: expectedCellWidth, height: pickerHeight)
    private static let borderWidth: CGFloat = 1
    private static let maxPhotoCount = 20
    
    private let photoSession = AVCaptureSession()
    private let stillImageOutput = AVCaptureStillImageOutput()
    private var captureLayer: AVCaptureVideoPreviewLayer!
    private let q = dispatch_queue_create("camera_load_q", DISPATCH_QUEUE_SERIAL)
    
    private let window = UIApplication.sharedApplication().keyWindow!
    private let manager = PHImageManager.defaultManager()
    
    var delegate: ImagePickerDelegate?
    
    ///////////////////////////////////////
    // Photo Assets
    ///////////////////////////////////////
    
    private var recentPhotos: [PHAsset] = []
    
    convenience init() {
        self.init(nibName: nil, bundle: nil)
        setUp()
    }
    
    ///////////////////////////////////////
    // Views
    ///////////////////////////////////////
    
    private let pickerContainer: UIView = {
        let v = UIView(frame: CGRect(x: 0, y: screenSize.height, width: screenSize.width, height: pickerHeight))
        v.backgroundColor = UIColor.whiteColor()
        v.layer.shadowRadius = 2
        v.layer.shadowOpacity = 0.1
        v.layer.shadowColor = UIColor.blackColor().CGColor
        return v
        }()
    
    private var backgroundView: UIView = {
        let v = UIView(frame: UIScreen.mainScreen().bounds)
        v.backgroundColor = UIColor.blackColor().colorWithAlphaComponent(0.4)
        v.alpha = 0
        v.userInteractionEnabled = true
        return v
        }()
    
    private var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .Horizontal
        layout.estimatedItemSize = targetSize
        layout.minimumInteritemSpacing = borderWidth
        layout.minimumLineSpacing = 0
        var cv = UICollectionView(frame: CGRect(x: 0, y: 0, width: screenSize.width, height: pickerHeight), collectionViewLayout: layout)
        cv.backgroundColor = UIColor.whiteColor()
        return cv
        }()
    
    
    ///////////////////////////////////////
    //  UIViewController Lifecycle
    ///////////////////////////////////////
    
    override func viewDidLoad() {
        super.viewDidLoad()
        collectionView.delegate = self
        collectionView.dataSource = self
        collectionView.registerClass(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        collectionView.registerClass(CameraCell.self, forCellWithReuseIdentifier: CameraCell.reuseIdentifier)
        
        let opts = PHFetchOptions()
        opts.sortDescriptors = [
            NSSortDescriptor(key: "creationDate", ascending: false)
        ]
        if let photos = PHAsset.fetchAssetsWithMediaType(.Image, options: opts) {
            let max = min(ImagePickerViewController.maxPhotoCount, photos.count)
            let indexes = NSIndexSet(indexesInRange: NSMakeRange(0, max))
            recentPhotos = photos.objectsAtIndexes(indexes).map { $0 as! PHAsset }
        }
        pickerContainer.addSubview(collectionView)
        initCamera()
    }
    
    ///////////////////////////////////////
    //  CollectionView
    ///////////////////////////////////////
    
    func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 2
    }
    
    func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch(section){
        case 0:
            return 1
        case 1:
            return min(recentPhotos.count, ImagePickerViewController.maxPhotoCount)
        default:
            fatalError("Don't know about section \(section)")
        }
    }
    
    func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(CameraCell.reuseIdentifier, forIndexPath: indexPath) as! CameraCell
            let bg = UIView(frame: cell.bounds)
            cell.backgroundView = bg
            showCameraPreview(cell.backgroundView!.layer)
            return cell
        } else if indexPath.section == 1 {
            var cell = collectionView.dequeueReusableCellWithReuseIdentifier(PhotoCell.reuseIdentifier, forIndexPath: indexPath) as! PhotoCell
            if cell.tag != 0 {
                manager.cancelImageRequest(PHImageRequestID(cell.tag))
            }
            cell.tag = Int(manager.requestImageForAsset(recentPhotos[indexPath.row], targetSize: ImagePickerViewController.targetSize, contentMode: .AspectFit, options: nil) { (result, _) in
                cell.image = result
            })
            return cell
        } else {
            fatalError("Don't know about section \(indexPath.section)")
        }
    }
    
    func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if indexPath.section == 0 {
            capturePhoto { photo in
                self.delegate?.didSelectImage(photo)
            }
        } else if indexPath.section == 1 {
            let asset = recentPhotos[indexPath.row]
            manager.requestImageForAsset(asset, targetSize: PHImageManagerMaximumSize, contentMode: .AspectFit, options: nil) { (result, _) in
                self.delegate?.didSelectImage(result)
            }
        }
        dismissPicker(false)
    }
    
    /////////////////////////////////////////
    // Public API
    /////////////////////////////////////////
    
    func dismissPicker(animated: Bool) {
        UIView.animateWithDuration(0.2, animations: {
            self.backgroundView.alpha = 0
            self.pickerContainer.transform = CGAffineTransformIdentity
            }) { _ in
                self.dismissViewControllerAnimated(animated, completion: nil)
                self.pickerContainer.removeFromSuperview()
                self.backgroundView.removeFromSuperview()
        }
    }
    
    func show(fromVc vc: UIViewController) {
        vc.presentViewController(self, animated: true, completion: nil)
        UIView.animateWithDuration(0.24) {
            self.backgroundView.alpha = 1
            self.pickerContainer.transform = CGAffineTransformMakeTranslation(0, -ImagePickerViewController.pickerHeight)
        }
    }
    
    /////////////////////////////////////////
    // Private Helper
    /////////////////////////////////////////
    
    private func setUp() {
        self.modalPresentationStyle = .OverCurrentContext
        view.backgroundColor = UIColor.clearColor()
        backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action:"onOutsideTap"))
        window.addSubview(backgroundView)
        window.addSubview(pickerContainer)
    }
    
    func onOutsideTap() {
        dismissPicker(true)
    }
    
    ///////////////////////////////////////
    //  Camera
    ///////////////////////////////////////
    
    private func initCamera() {
        let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        let input = AVCaptureDeviceInput(device: device, error: nil)
        
        if let input = input {
            photoSession.addInput(input)
        }
        stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        if photoSession.canAddOutput(stillImageOutput) {
            photoSession.addOutput(stillImageOutput)
        }
        photoSession.sessionPreset = AVCaptureSessionPresetPhoto
        
        photoSession.startRunning()
        captureLayer = AVCaptureVideoPreviewLayer.layerWithSession(photoSession) as! AVCaptureVideoPreviewLayer
        captureLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
    }
    
    private func showCameraPreview(layer: CALayer) {
        captureLayer.frame = layer.bounds
        layer.addSublayer(self.captureLayer)
    }
    
    private func capturePhoto(handler: UIImage -> ()) {
        doInBackground(q: q) {
            if let connection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo) {
                connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.currentDevice().orientation.rawValue)!
                self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(connection) { (imageDataSampleBuffer, error) in
                    if let buffer = imageDataSampleBuffer {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                        doOnUIThread { handler(UIImage(data: imageData)!) }
                    } else {
                        FLOG.e(error)
                    }
                }
            }
        }
        
    }
    
    private func imageFromCaptureLayer() -> UIImage {
        UIGraphicsBeginImageContext(captureLayer.frame.size)
        captureLayer.renderInContext(UIGraphicsGetCurrentContext())
        return UIGraphicsGetImageFromCurrentImageContext()
    }
}

private class PhotoCell: UICollectionViewCell {
    static let reuseIdentifier = "ImagePickerCell"
    let imageView = UIImageView()
    var image: UIImage? {
        didSet {
            imageView.image = image
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.whiteColor()
        imageView.contentMode = .ScaleAspectFit
        
        imageView.setTranslatesAutoresizingMaskIntoConstraints(false)
        addSubview(imageView)
        
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Left, relatedBy: .Equal, toItem: self, attribute: .Left, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Right, relatedBy: .Equal, toItem: self, attribute: .Right, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Top, relatedBy: .Equal, toItem: self, attribute: .Top, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Bottom, relatedBy: .Equal, toItem: self, attribute: .Bottom, multiplier: 1.0, constant: 0))
        
        layoutIfNeeded()
    }
    
    override func preferredLayoutAttributesFittingAttributes(layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes! {
        let attr = UICollectionViewLayoutAttributes()
        let imageSize = imageView.image!.size
        let scalar = imageView.bounds.size.height / imageSize.height
        attr.size = CGSize(width: imageSize.width * scalar, height: imageSize.height * scalar)
        return attr
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

private class CameraCell: UICollectionViewCell {
    static let reuseIdentifier = "CameraCell"
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.blackColor()
        initView()
    }
    
    override func preferredLayoutAttributesFittingAttributes(layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes! {
        let attr = UICollectionViewLayoutAttributes()
        attr.size = CGSize(width: ImagePickerViewController.expectedCellWidth, height: bounds.size.height)
        return attr
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initView() {
        doOnUIThread {
            let borderWidth: CGFloat = ImagePickerViewController.borderWidth
            let border = UIView(frame: CGRect(x: self.bounds.size.width - borderWidth, y: 0, width: borderWidth, height: self.bounds.size.height))
            border.backgroundColor = UIColor.whiteColor()
            self.contentView.addSubview(border)
            let sendColor = UIColor.whiteColor().colorWithAlphaComponent(0.4)
            let send = UIImageView(imageNamed: "ic_send_48pt", color: sendColor)!
            self.contentView.addSubview(send)
            send.center = self.convertPoint(self.center, toView: self.superview)
        }
    }
}

