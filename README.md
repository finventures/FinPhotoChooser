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

#### Cocoapods
Include via your `Podfile`:

`pod 'FinPhotoChooser', '~> 2.2.0'`
