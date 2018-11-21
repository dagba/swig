#
# Be sure to run `pod lib lint Swig.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "Swig"
  s.version          = "0.3.38"
  s.summary          = "PJSIP Wrapper for ios"
  s.description      = <<-DESC
                       Simplifing the use of pjsip on ios
                       DESC
  s.homepage         = "https://github.com/petester42/swig"
  s.license          = 'MIT'
  s.author           = { "Pierre-Marc Airoldi" => "pierremarcairoldi@gmail.com" }
  s.source           = { :git => "https://github.com/petester42/swig.git", :tag => s.version.to_s }
  s.social_media_url = 'https://twitter.com/petester42'

  s.platform     = :ios, '8.0'
  s.requires_arc = true

  s.resources = 'Pod/Assets/*', 'Pod/SoundSwitch/*.caf'
  s.source_files = 'Pod/Classes/**/*{c,h,m}', 'Pod/SoundSwitch/*{h,m}'
  s.preserve_paths = 'Pod/Classes/**/*{c,h,m}', 'Pod/SoundSwitch/*{h,m}', 'Pod/openfec/include/**/*{h}'

  s.vendored_libraries = 'Pod/openfec/lib/*.a'

  s.dependency 'AFNetworking/Reachability', '~> 3'
  s.dependency 'libextobjc', '~> 0.4'
  s.dependency 'CocoaLumberjack', '2.0.0-rc'
  s.dependency 'FCUUID', '~> 1.1'
  s.dependency 'pjsip-ios', '~> 0.1'

  s.xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) PJ_AUTOCONF=1',
    'HEADER_SEARCH_PATHS'  => '$(inherited) $(PODS_ROOT)/pjsip-ios/Pod/pjsip-include $(SOURCE_ROOT)/../Pod/pjsip-include $(PODS_ROOT)/Swig/Pod/openfec/include'
  }

end
