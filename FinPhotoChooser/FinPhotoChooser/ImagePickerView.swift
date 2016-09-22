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
    func didSelectImage(_ image: UIImage)
}

open class ImagePickerView: UIView, UICollectionViewDataSource, UICollectionViewDelegate, UICollectionViewDelegateFlowLayout, UIImagePickerControllerDelegate, UINavigationControllerDelegate, PHPhotoLibraryChangeObserver {

    fileprivate static let screenSize = UIScreen.main.bounds.size
    fileprivate static let expectedCellWidth: CGFloat = 240
    fileprivate static let borderWidth: CGFloat = 1
    fileprivate static let bgColor = UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)
    fileprivate static let defaultFetchOptions: PHFetchOptions = {
        let opts = PHFetchOptions()
        opts.sortDescriptors = [ NSSortDescriptor(key: "creationDate", ascending: false) ]
        return opts
    }()

    fileprivate let photoSession = AVCaptureSession()
    fileprivate let photoSessionPreset: String
    fileprivate let stillImageOutput = AVCaptureStillImageOutput()
    fileprivate let cachingImageManager = PHCachingImageManager()
    fileprivate var captureLayer: AVCaptureVideoPreviewLayer!
    fileprivate let q = DispatchQueue(label: "camera_load_q", attributes: [])
    fileprivate let dismissOnTap: Bool
    
    fileprivate var targetSize: CGSize { return CGSize(width: ImagePickerView.expectedCellWidth, height: frame.height) }

    open var delegate: ImagePickerDelegate?

    ///////////////////////////////////////
    // Photo Assets
    ///////////////////////////////////////

    open var maxPhotoCount = 20 {
        didSet {
            fetchImageAssets()
        }
    }

    open let targetImageSize: CGSize

    open var recentPhotos: [PHAsset] = [] {
        willSet {
            cachingImageManager.stopCachingImagesForAllAssets()
        }
        didSet {
            cachingImageManager.startCachingImages(for: self.recentPhotos, targetSize: targetImageSize, contentMode: .aspectFit, options: nil)
        }
    }

    open func photoLibraryDidChange(_ changeInfo: PHChange) {
        fetchImageAssets()
    }

    ///////////////////////////////////////
    // Initialization
    ///////////////////////////////////////

    public init(frame: CGRect, targetImageSize: CGSize = PHImageManagerMaximumSize, cameraPreset: String = AVCaptureSessionPresetPhoto, dismissOnTap: Bool = true) {
        self.dismissOnTap = dismissOnTap
        self.targetImageSize = targetImageSize
        self.photoSessionPreset = cameraPreset
        super.init(frame: frame)
        setUp()
        self.collectionView.delegate = self
        self.collectionView.dataSource = self
        self.collectionView.register(PhotoCell.self, forCellWithReuseIdentifier: PhotoCell.reuseIdentifier)
        self.collectionView.register(CameraCell.self, forCellWithReuseIdentifier: CameraCell.reuseIdentifier)
        
        addSubview(self.collectionView)
    }

    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    ///////////////////////////////////////
    // Views
    ///////////////////////////////////////

    fileprivate var backgroundView: UIView = {
        let v = UIView(frame: UIScreen.main.bounds)
        v.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        v.alpha = 0
        v.isUserInteractionEnabled = true
        return v
    }()

    fileprivate var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = borderWidth
        layout.minimumLineSpacing = 0
        var cv = UICollectionView(frame: .zero, collectionViewLayout: layout)
        cv.backgroundColor = ImagePickerView.bgColor
        return cv
    }()

    ///////////////////////////////////////
    //  CollectionView
    ///////////////////////////////////////

    open func numberOfSections(in collectionView: UICollectionView) -> Int {
        return 2
    }

    open func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        switch(section){
        case 0:
            return 1
        case 1:
            return min(recentPhotos.count, maxPhotoCount)
        default:
            fatalError("Don't know about section \(section)")
        }
    }

    open func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if (indexPath as NSIndexPath).section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: CameraCell.reuseIdentifier, for: indexPath) as! CameraCell
            let bg = UIView(frame: cell.bounds)
            cell.backgroundView = bg
            showCameraPreview(cell.backgroundView!.layer)
            return cell
        } else if (indexPath as NSIndexPath).section == 1 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: PhotoCell.reuseIdentifier, for: indexPath) as! PhotoCell
            let o = PHImageRequestOptions()
            o.isSynchronous = true
            let photo = recentPhotos[(indexPath as NSIndexPath).row]
            cachingImageManager.requestImage(for: photo, targetSize: targetSize, contentMode: .aspectFit, options: o) { (result, _) in
                cell.image = result
            }
            return cell
        } else {
            fatalError("Don't know about section \((indexPath as NSIndexPath).section)")
        }
    }

    open func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        if (indexPath as NSIndexPath).section == 0 {
            capturePhoto { photo in
                self.delegate?.didSelectImage(photo)
            }
        } else if (indexPath as NSIndexPath).section == 1 {
            let asset = recentPhotos[(indexPath as NSIndexPath).row]
            let syncOpt = PHImageRequestOptions()
            syncOpt.isSynchronous = true
            cachingImageManager.requestImage(for: asset, targetSize: targetImageSize, contentMode: .aspectFit, options: syncOpt) { (result, _) in
                self.delegate?.didSelectImage(result!)
            }
        }
    }

    /////////////////////////////////////////
    // Private Helper
    /////////////////////////////////////////

    fileprivate func setUp() {
        fetchImageAssets()
        if PHPhotoLibrary.authorizationStatus() != .authorized {
            PHPhotoLibrary.requestAuthorization { status in
                if status == .authorized {
                    self.fetchImageAssets()
                }
            }
        }
        PHPhotoLibrary.shared().register(self)
        initCamera()
    }
    
    override open var frame: CGRect {
        didSet {
            collectionView.collectionViewLayout.invalidateLayout()
            collectionView.frame = CGRect(x: 0, y: 0, width: frame.width, height: frame.height)
            (collectionView.collectionViewLayout as! UICollectionViewFlowLayout).estimatedItemSize = CGSize(width: ImagePickerView.expectedCellWidth, height: frame.height)
        }
    }

    fileprivate func fetchImageAssets() {
        let photos = PHAsset.fetchAssets(with: .image, options: ImagePickerView.defaultFetchOptions)
        let max = min(maxPhotoCount, photos.count)
        let indexes = IndexSet(integersIn: NSMakeRange(0, max).toRange()!)
        recentPhotos = photos.objects(at: indexes).map { $0 }
        collectionView.reloadData()
    }


    ///////////////////////////////////////
    //  Camera
    ///////////////////////////////////////

    fileprivate func initCamera() {
        let device = AVCaptureDevice.defaultDevice(withMediaType: AVMediaTypeVideo)

        if let input = try? AVCaptureDeviceInput(device: device) {
            photoSession.addInput(input)
        }
        stillImageOutput.outputSettings = [AVVideoCodecKey: AVVideoCodecJPEG]
        if photoSession.canAddOutput(stillImageOutput) {
            photoSession.addOutput(stillImageOutput)
        }
        if photoSession.canSetSessionPreset(photoSessionPreset) {
            photoSession.sessionPreset = photoSessionPreset
        }

        photoSession.startRunning()
        captureLayer = AVCaptureVideoPreviewLayer(session: photoSession)
        captureLayer.videoGravity = AVLayerVideoGravityResizeAspectFill
    }

    fileprivate func showCameraPreview(_ layer: CALayer) {
        captureLayer.frame = layer.bounds
        layer.addSublayer(self.captureLayer)
    }

    fileprivate func capturePhoto(_ handler: @escaping (UIImage) -> ()) {
        q.async {
            if let connection = self.stillImageOutput.connection(withMediaType: AVMediaTypeVideo) {
                connection.videoOrientation = AVCaptureVideoOrientation(rawValue: UIDevice.current.orientation.rawValue)!
                self.stillImageOutput.captureStillImageAsynchronously(from: connection) { (imageDataSampleBuffer, error) in
                    if let _ = imageDataSampleBuffer {
                        let imageData = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(imageDataSampleBuffer)
                        DispatchQueue.main.async { handler(UIImage(data: imageData!)!) }
                    }
                }
            }
        }

    }

    fileprivate func imageFromCaptureLayer() -> UIImage {
        UIGraphicsBeginImageContext(captureLayer.frame.size)
        captureLayer.render(in: UIGraphicsGetCurrentContext()!)
        return UIGraphicsGetImageFromCurrentImageContext()!
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
        backgroundColor = ImagePickerView.bgColor
        imageView.contentMode = .scaleAspectFit

        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        addConstraint(NSLayoutConstraint(item: imageView, attribute: .left, relatedBy: .equal, toItem: contentView, attribute: .left, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .right, relatedBy: .equal, toItem: contentView, attribute: .right, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .top, relatedBy: .equal, toItem: contentView, attribute: .top, multiplier: 1.0, constant: 0))
        addConstraint(NSLayoutConstraint(item: imageView, attribute: .bottom, relatedBy: .equal, toItem: contentView, attribute: .bottom, multiplier: 1.0, constant: 0))

        layoutIfNeeded()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attr = super.preferredLayoutAttributesFitting(layoutAttributes)
        let imageSize = imageView.image!.size
        let scalar = imageView.bounds.height / imageSize.height
        attr.size = CGSize(width: imageSize.width * scalar, height: attr.size.height)
        return attr
    }

    required init(coder aDecoder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

private class CameraCell: UICollectionViewCell {
    static let reuseIdentifier = "CameraCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = UIColor.black
        initView()
    }

    override func preferredLayoutAttributesFitting(_ layoutAttributes: UICollectionViewLayoutAttributes) -> UICollectionViewLayoutAttributes {
        let attr = UICollectionViewLayoutAttributes()
        attr.size = CGSize(width: ImagePickerView.expectedCellWidth, height: contentView.bounds.height)
        return attr
    }

    required init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    fileprivate func initView() {
        let borderWidth: CGFloat = ImagePickerView.borderWidth
        let border = UIView(frame: CGRect(x: self.bounds.size.width - borderWidth, y: 0, width: borderWidth, height: contentView.bounds.size.height))
        border.backgroundColor = ImagePickerView.bgColor
        self.contentView.addSubview(border)
        let sendColor = UIColor.white.withAlphaComponent(0.4)
        var sendImg = UIImage(named: "ic_send_48pt.png", in: Bundle(for: ImagePickerView.self), compatibleWith: nil)!
        sendImg = UIImage(cgImage: sendImg.cgImage!, scale: 3, orientation: sendImg.imageOrientation)
        sendImg = sendImg.withRenderingMode(.alwaysTemplate)
        let send = UIImageView(image: sendImg)
        send.tintColor = sendColor
        self.contentView.addSubview(send)
        send.center = self.convert(self.center, to: self.superview)
    }
}

