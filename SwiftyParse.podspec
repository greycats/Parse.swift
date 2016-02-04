Pod::Spec.new do |s|
  s.name             = "SwiftyParse"
  s.version          = "1.0.5"
  s.summary          = "Parse client in Swift. Do it right."
  s.homepage         = "https://github.com/greycats/Parse.swift"
  s.license          = 'MIT'
  s.author           = { "Rex Sheng" => "https://github.com/b051" }
  s.source           = { :git => "https://github.com/greycats/Parse.swift.git", :tag => s.version.to_s }
  s.requires_arc     = true
  s.platform         = :ios, "8.0"
  
  s.source_files = "Parse/*.swift"
  s.dependency 'Alamofire'

end
