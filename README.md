# FinPhotoChooser
iOS photo chooser optimized for swiftness

![alt preview](recording.gif)

#### Features
 - Retrieve latest `n` photos from a device's Photos framework
 - Camera preview and capture in line with recent photos
 - Configure image quality
 - Fetched assets cached upon fetch
 - Photos framework permissions
 
#### Usage
(requires Xcode 7, written with Swift 2)
```swift
class MyVC: UIViewController, ImagePickerDelegate {
 
 // ...
 
 func showChooser() {
  let picker = ImagePickerViewController()
  picker.delegate = self
  picker.show(fromVc: self) 
 }
 
 func didSelectImage(image: UIImage) {
  // do something with selected image
 }
}
```

#### Cocoapods
Include via your `Podfile`:

`pod 'FinPhotoChooser', '~> 2.0.5'`
