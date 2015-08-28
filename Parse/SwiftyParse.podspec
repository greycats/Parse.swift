#
# Be sure to run `pod lib lint Greycats.swift.podspec' to ensure this is a
# valid spec and remove all comments before submitting the spec.
#
# Any lines starting with a # are optional, but encouraged
#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = "SwiftyParse"
  s.version          = "0.8.0"
  s.summary          = "Parse client in Swift. Do it right."
  s.homepage         = "https://github.com/greycats/Parse.swift"
  s.license          = 'MIT'
  s.author           = { "Rex Sheng" => "https://github.com/b051" }
  s.source           = { :git => "https://github.com/greycats/Parse.swift.git", :tag => s.version.to_s }
  s.requires_arc     = true

  s.source_files = "Parse/*.swift"
  s.dependency 'Alamofire'

end
