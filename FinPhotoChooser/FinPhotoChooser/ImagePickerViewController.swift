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

public protocol ImagePickerDelegate {
    func didSelectImage(image: UIImage)
}

public class ImagePickerViewController: UIViewController, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPhotoLibraryChangeObserver {
    
    private static let screenSize = UIScreen.mainScreen().bounds.size
    private static let expectedCellWidth: CGFloat = 240
    private static let borderWidth: CGFloat = 1
    private static let bgColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    private static let defaultFetchOptions: PHFetchOptions = {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: false) ]
        return opts
        }()
    
    private let pickerHeight: CGFloat
    private var targetSize: CGSize { return CGSize(width: ImagePickerViewController.expectedCellWidth, height: pickerHeight) }
    private let photoSession = AVCaptureSession()
    private let photoSessionPreset: String
    private let stillImageOutput = AVCaptureStillImageOutput()
    private let cachingImageManager = PHCachingImageManager()
    private var captureLayer: AVCaptureVideoPreviewLayer!
    private let q = dispatch_queue_create("camera_load_q", DISPATCH_QUEUE_SERIAL)
    
    public var delegate: ImagePickerDelegate?
    
    ///////////////////////////////////////
    // Photo Assets
    ///////////////////////////////////////
    
    public var maxPhotoCount = 20 {
        didSet {
            fetchImageAssets()
        }
    }
    
    public let targetImageSize: CGSize
    
    public var recentPhotos: [PHAsset] = [] {
        willSet {
            cachingImageManager.stopCachingImagesForAllAssets()
        }
        didSet {
            cachingImageManager.startCachingImagesForAssets(self.recentPhotos, targetSize: targetImageSize, contentMode: .AspectFit, options: nil)
        }
    }
    
    public func photoLibraryDidChange(changeInfo: PHChange) {
        fetchImageAssets()
    }
    
    ///////////////////////////////////////
    // Initialization
    ///////////////////////////////////////
    
    public init(targetImageSize: CGSize = PHImageManagerMaximumSize, cameraPreset: String = AVCaptureSessionPresetPhoto, pickerHeight: CGFloat = 280) {
        self.targetImageSize = targetImageSize
        self.photoSessionPreset = cameraPreset
        self.pickerHeight = pickerHeight
        super.init(nibName: nil, bundle: nil)
        let ss = ImagePickerViewController.screenSize
        pickerContainer.frame = CGRect(x: 0, y: ss.height, width: ss.width, height: pickerHeight)
        collectionView.frame = CGRect(x: 0, y: 0, width: ss.width, height: pickerHeight)
        (collectionView.collectionViewLayout as! UICollectionViewFlowLayout).estimatedItemSize = CGSize(width: ImagePickerViewController.expectedCellWidth, height: pickerHeight)
        setUp()
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    ///////////////////////////////////////
    // Views
    ///////////////////////////////////////
    
    private let pickerContainer: UIView = {
        let v = UIView(frame: .zero)
        v.backgroundColor = ImagePickerViewController.bgColor
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
        layout.minimumInteritemSpacing = borderWidth
        layout.minimumLineSpacing = 0
        var cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = ImagePickerViewController.bgColor
        return cv
        }()
    
    
    ///////////////////////////////////////
    //  UIViewController Lifecycle
    ///////////////////////////////////////
    
    public override func loadView() {
        super.loadView()
        initCamera()
    }
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        dispatch_async(dispatch_get_main_queue()) {
            self.collectionView.delegate = self
            self.collectionView.dataSource = self
            self.collectionView.registerClass(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
            self.collectionView.registerClass(CameraCell.self, forCellWithReuseIdentifier: CameraCell.reuseIdentifier)
            self.view.backgroundColor = UIColor.clearColor()
            self.backgroundView.addGestureRecognizer(UITapGestureRecognizer(target: self, action:"onOutsideTap"))
            
            self.pickerContainer.addSubview(self.collectionView)
        }
    }
    
    ///////////////////////////////////////
    //  CollectionView
    ///////////////////////////////////////
    
    public func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 2
    }
    
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch(section){
        case 0:
            return 1
        case 1:
            return min(recentPhotos.count, maxPhotoCount)
        default:
            fatalError("Don't know about section \(section)")
        }
    }
    
    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(CameraCell.reuseIdentifier, forIndexPath: indexPath) as! CameraCell
            let bg = UIView(frame: cell.bounds)
            cell.backgroundView = bg
            showCameraPreview(cell.backgroundView!.layer)
            return cell
        } else if indexPath.section == 1 {
            let cell = collectionView.dequeueReusableCellWithReuseIdentifier(PhotoCell.reuseIdentifier, forIndexPath: indexPath) as! PhotoCell
            if cell.tag != 0 {
                cachingImageManager.cancelImageRequest(PHImageRequestID(cell.tag))
            }
            cell.tag = Int(cachingImageManager.requestImageForAsset(recentPhotos[indexPath.row], targetSize: targetSize, contentMode: .AspectFit, options: nil) { (result, _) in
                cell.image = result
                })
            return cell
        } else {
            fatalError("Don't know about section \(indexPath.section)")
        }
    }
    
    public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if indexPath.section == 0 {
            capturePhoto { photo in
                self.delegate?.didSelectImage(photo)
            }
        } else if indexPath.section == 1 {
            let asset = recentPhotos[indexPath.row]
            let syncOpt = PHImageRequestOptions()
            syncOpt.synchronous = true
            cachingImageManager.requestImageForAsset(asset, targetSize: targetImageSize, contentMode: .AspectFit, options: syncOpt) { (result, _) in
                self.delegate?.didSelectImage(result!)
            }
        }
        dismissPicker(false)
    }
    
    /////////////////////////////////////////
    // Public API
    /////////////////////////////////////////
    
    public func dismissPicker(animated: Bool) {
        UIView.animateWithDuration(0.2, animations: {
            self.backgroundView.alpha = 0
            self.pickerContainer.transform = CGAffineTransformIdentity
            }) { _ in
                self.dismissViewControllerAnimated(false, completion: nil)
                self.pickerContainer.removeFromSuperview()
                self.backgroundView.removeFromSuperview()
        }
    }
    
    public func show(fromVc vc: UIViewController) {
        fetchImageAssets()
        collectionView.setContentOffset(CGPointZero, animated: false)
        let window = UIApplication.sharedApplication().keyWindow!
        window.addSubview(backgroundView)
        window.addSubview(pickerContainer)
        vc.presentViewController(self, animated: false, completion: nil)
        UIView.animateWithDuration(0.2, delay: 0, options: .CurveEaseIn, animations: {
            self.backgroundView.alpha = 1
            self.pickerContainer.transform = CGAffineTransformMakeTranslation(0, -self.pickerHeight)
            }, completion: nil)
    }
    
    /////////////////////////////////////////
    // Private Helper
    /////////////////////////////////////////
    
    private func setUp() {
        self.modalPresentationStyle = .OverCurrentContext
        fetchImageAssets()
        if PHPhotoLibrary.authorizationStatus() != .Authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .Authorized {
                    self.fetchImageAssets()
                }
            }
        }
        PHPhotoLibrary.sharedPhotoLibrary().registerChangeObserver(self)
    }
    
    private func fetchImageAssets() {
        let photos = PHAsset.fetchAssetsWithMediaType(.Image, options: ImagePickerViewController.defaultFetchOptions)
        let max = min(maxPhotoCount, photos.count)
        let indexes = NSIndexSet(indexesInRange: NSMakeRange(0, max))
        recentPhotos = photos.objectsAtIndexes(indexes).map { $0 as! PHAsset }
        collectionView.reloadData()
    }
    
    func onOutsideTap() {
        dismissPicker(true)
    }
    
    
    ///////////////////////////////////////
    //  Camera
    ///////////////////////////////////////
    
    private func initCamera() {
        let device = AVCaptureDevice.defaultDeviceWithMediaType(AVMediaTypeVideo)
        
        if let input = try? AVCaptureDeviceInput(device: device) {
            photoSession.addInput(input)
        }
        stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        if photoSession.canAddOutput(stillImageOutput) {
            photoSession.addOutput(stillImageOutput)
        }
        photoSession.sessionPreset = photoSessionPreset
        
        photoSession.startRunning()
        captureLayer = AVCaptureVideoPreviewLayer(session: photoSession)
        captureLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
    }
    
    private func showCameraPreview(layer: CALayer) {
        captureLayer.frame = layer.bounds
        layer.addSublayer(self.captureLayer)
    }
    
    private func capturePhoto(handler: UIImage -> ()) {
        dispatch_async(q) {
            if let connection = self.stillImageOutput.connectionWithMediaType(AVMediaTypeVideo) {
                connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.currentDevice().orientation.rawValue)!
                self.stillImageOutput.captureStillImageAsynchronouslyFromConnection(connection) { (imageDataSampleBuffer, error) in
                    if let _ = imageDataSampleBuffer {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                        dispatch_async(dispatch_get_main_queue()) { handler(UIImage(data: imageData)!) }
                    }
                }
            }
        }
        
    }
    
    private func imageFromCaptureLayer() -> UIImage {
        UIGraphicsBeginImageContext(captureLayer.frame.size)
        captureLayer.renderInContext(UIGraphicsGetCurrentContext()!)
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
        backgroundColor = ImagePickerViewController.bgColor
        imageView.contentMode = .ScaleAspectFit
        
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Left, relatedBy: .Equal, toItem: self, attribute: .Left, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Right, relatedBy: .Equal, toItem: self, attribute: .Right, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Top, relatedBy: .Equal, toItem: self, attribute: .Top, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .Bottom, relatedBy: .Equal, toItem: self, attribute: .Bottom, multiplier: 1.0, constant: 0))
        
        layoutIfNeeded()
    }
    
    override func preferredLayoutAttributesFittingAttributes(layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
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
    
    override func preferredLayoutAttributesFittingAttributes(layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attr = UICollectionViewLayoutAttributes()
        attr.size = CGSize(width: ImagePickerViewController.expectedCellWidth, height: bounds.size.height)
        return attr
    }
    
    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func initView() {
        dispatch_async(dispatch_get_main_queue()) {
            let borderWidth: CGFloat = ImagePickerViewController.borderWidth
            let border = UIView(frame: CGRect(x: self.bounds.size.width - borderWidth, y: 0, width: borderWidth, height: self.bounds.size.height))
            border.backgroundColor = ImagePickerViewController.bgColor
            self.contentView.addSubview(border)
            let sendColor = UIColor.whiteColor().colorWithAlphaComponent(0.4)
            var sendImg = UIImage(named: "ic_send_48pt.png", inBundle: NSBundle(forClass: ImagePickerViewController.self), compatibleWithTraitCollection: nil)!
            sendImg = UIImage(CGImage: sendImg.CGImage!, scale: 3, orientation: sendImg.imageOrientation)
            sendImg = sendImg.imageWithRenderingMode(.AlwaysTemplate)
            let send = UIImageView(image: sendImg)
            send.tintColor = sendColor
            self.contentView.addSubview(send)
            send.center = self.convertPoint(self.center, toView: self.superview)
        }
    }
}

