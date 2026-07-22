Pod::Spec.new do |s|
  s.name          = 'DatadogSDKTesting'
  s.module_name   = 'DatadogSDKTesting'
  s.version       = '2.7.7-alpha3'
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
    :sha256 => '8347e324a03412899286e62063e75280cb8cfa8db66fce357d220ace3e316a13'
  }
  
  s.ios.deployment_target     = '15.0'
  s.osx.deployment_target     = '11.0'
  s.tvos.deployment_target    = '15.0'
  s.watchos.deployment_target = '8.0'
  s.visionos.deployment_target = '1.0'
  
  s.vendored_frameworks    = 'DatadogSDKTesting.xcframework'
end
