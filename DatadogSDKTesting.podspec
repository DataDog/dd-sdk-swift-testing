Pod::Spec.new do |s|
  s.name          = 'DatadogSDKTesting'
  s.module_name   = 'DatadogSDKTesting'
  s.version       = '2.7.4'
  s.summary       = "Swift testing framework for Datadog's CI Visibility product"
  s.license       = 'Apache 2.0'
  s.homepage      = 'https://www.datadoghq.com'
  s.social_media_url = 'https://twitter.com/datadoghq'
  
  s.swift_version = '5.9'

  s.authors = {
    'Yehor Popovych'  => 'yehor.popovych@datadoghq.com',
    'Nacho Bonafonte' => 'nacho.bonafontearruga@datadoghq.com'
  }
  
  s.source = {
    :http => "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/#{s.version}/DatadogSDKTesting.zip",
    :sha256 => 'b80c80289e1c82e3bf798fd9c17278d5344571c8941831e92a8fb10a93a8cdd7'
  }
  
  s.ios.deployment_target     = '15.0'
  s.osx.deployment_target     = '11.0'
  s.tvos.deployment_target    = '15.0'
  s.watchos.deployment_target = '8.0'
  s.visionos.deployment_target = '1.0'
  
  s.vendored_frameworks    = 'DatadogSDKTesting.xcframework'
end
