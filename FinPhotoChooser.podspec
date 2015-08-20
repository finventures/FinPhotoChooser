Pod::Spec.new do |s|
  s.platform = :ios
  s.ios.deployment_target = '8.0'
  s.name = "FinPhotoChooser"
  s.summary = "iOS photo chooser optimized for swiftness"
  s.requires_arc = true
  s.version = "0.1.0"
  s.license = { :type => "MIT", :file => "LICENSE" }
  s.author = { "Fin Ventures" => "kousun12@gmail.com" }
  s.homepage = "https://www.fin.ventures/"

  s.source = { :git => "https://github.com/finventures/FinPhotoChooser.git", :tag => "#{s.version}"}

  s.framework = "UIKit"
  s.source_files = "FinPhotoChooser/**/*.swift"
  s.resources = "FinPhotoChooser/**/*.{png,jpeg,jpg,storyboard,xib}"
end
