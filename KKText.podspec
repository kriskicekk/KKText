Pod::Spec.new do |s|
  s.name         = 'KKText'
  s.summary      = 'Powerful text framework for iOS and macOS to display and edit rich text.'
  s.version      = '0.1.0'
  s.license      = { :type => 'MIT', :file => 'LICENSE' }
  s.authors      = { 'kris' => 'kriskice9527@gmail.com' }
  s.social_media_url = 'https://github.com/kriskicekk'
  s.homepage     = 'https://github.com/kriskicekk/KKText'
  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '14.0'
  s.source       = { :git => 'https://github.com/kriskicekk/KKText.git', :tag => s.version.to_s }
  
  s.requires_arc = true
  s.ios.source_files = 'KKText/**/*.{h,m}'
  s.ios.exclude_files = 'KKText/Platform/AppKit/**/*'
  s.ios.public_header_files = [
    'KKText/*.h',
    'KKText/String/**/*.h',
    'KKText/Component/**/*.h',
    'KKText/Utility/**/*.h'
  ]
  s.ios.frameworks = 'UIKit', 'CoreFoundation','CoreText', 'QuartzCore', 'Accelerate', 'MobileCoreServices'

  s.osx.source_files = [
    'KKText/KKText.{h}',
    'KKText/KKTextPlatform.{h,m}',
    'KKText/KKTextView.h',
    'KKText/Platform/AppKit/NSBezierPath+KKText.{h,m}',
    'KKText/Platform/AppKit/NSImage+KKText.{h,m}',
    'KKText/Platform/AppKit/NSValue+KKText.{h,m}',
    'KKText/Platform/AppKit/NSView+KKText.{h,m}',
    'KKText/Platform/AppKit/KKTextViewAppKit.m',
    'KKText/Platform/AppKit/KKTextViewDocumentView.{h,m}',
    'KKText/Platform/AppKit/KKTextViewParagraphContainerView.{h,m}',
    'KKText/Platform/AppKit/KKTextViewSelectionView.{h,m}',
    'KKText/KKLabel.{h,m}',
    'KKText/String/**/*.{h,m}',
    'KKText/Component/KKTextDebugOption.{h,m}',
    'KKText/Component/KKTextInput.{h,m}',
    'KKText/Component/KKTextLayout.{h,m}',
    'KKText/Component/KKTextLine.{h,m}',
    'KKText/Utility/KKTextAsyncLayer.{h,m}',
    'KKText/Utility/KKTextTransaction.{h,m}',
    'KKText/Utility/KKTextUtilities.{h,m}',
    'KKText/Utility/KKTextWeakProxy.{h,m}',
    'KKText/Utility/NSAttributedString+KKText.{h,m}',
    'KKText/Utility/NSParagraphStyle+KKText.{h,m}',
    'KKText/Utility/UIView+KKText.{h,m}'
  ]
  s.osx.public_header_files = [
    'KKText/KKText.h',
    'KKText/KKTextPlatform.h',
    'KKText/KKTextView.h',
    'KKText/Platform/AppKit/NSBezierPath+KKText.h',
    'KKText/Platform/AppKit/NSImage+KKText.h',
    'KKText/Platform/AppKit/NSValue+KKText.h',
    'KKText/Platform/AppKit/NSView+KKText.h',
    'KKText/KKLabel.h',
    'KKText/String/**/*.h',
    'KKText/Component/KKTextDebugOption.h',
    'KKText/Component/KKTextInput.h',
    'KKText/Component/KKTextLayout.h',
    'KKText/Component/KKTextLine.h',
    'KKText/Utility/KKTextAsyncLayer.h',
    'KKText/Utility/KKTextTransaction.h',
    'KKText/Utility/KKTextUtilities.h',
    'KKText/Utility/KKTextWeakProxy.h',
    'KKText/Utility/NSAttributedString+KKText.h',
    'KKText/Utility/NSParagraphStyle+KKText.h',
    'KKText/Utility/UIView+KKText.h'
  ]
  s.osx.frameworks = 'AppKit', 'CoreFoundation', 'CoreText', 'QuartzCore', 'Accelerate'

end
