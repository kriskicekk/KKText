Pod::Spec.new do |s|
  s.name         = 'KKText'
  s.summary      = 'Powerful text framework for iOS to display and edit rich text.'
  s.version      = '0.1.0'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'kris' => 'kriskice9527@gmail.com' }
  s.social_media_url = 'https://github.com/kriskicekk'
  s.homepage     = 'https://github.com/kriskicekk/KKText'
  s.platform     = :ios, '10.0'
  s.ios.deployment_target = '10.0'
  s.source       = { :git => 'https://github.com/kriskicekk/KKText.git', :tag => s.version.to_s }
  
  s.requires_arc = true
  s.source_files = 'KKText/**/*.{h,m}'
  s.public_header_files = 'KKText/**/*.{h}'
  
  s.frameworks = 'UIKit', 'CoreFoundation','CoreText', 'QuartzCore', 'Accelerate', 'MobileCoreServices'

end
