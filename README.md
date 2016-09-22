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

The current version requires Xcode 8, written with Swift 3

(3.2.0 is the latest Swift 2.2 version)

  ```swift
  class MyVC: UIViewController, ImagePickerDelegate {

    // ...

    func showChooser() {
      let screen = UIScreen.mainScreen().bounds
        let picker = ImagePickerView(frame: CGRect(x: 0, y: 0, width: screen.width, height: 255))
        view.addSubview(picker)
        picker.delegate = self
    }

    func didSelectImage(image: UIImage) {
      // do something with selected image
    }
  }
```

#### CocoaPods
Include via your `Podfile`:

`pod 'FinPhotoChooser', '~> 4.0.0'`
