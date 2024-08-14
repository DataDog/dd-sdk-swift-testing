Pod::Spec.new do |s|
  s.name          = 'DatadogSDKTesting'
  s.module_name   = 'DatadogSDKTesting'
  s.version       = '2.5.0-alpha3'
  s.summary       = "Swift testing framework for Datadog's CI Visibility product"
  s.license       = 'Apache 2.0'
  s.homepage      = 'https://www.datadoghq.com'
  s.social_media_url = 'https://twitter.com/datadoghq'
  
  s.swift_version = '5.7.1'

  s.authors = {
    'Yehor Popovych'  => 'yehor.popovych@datadoghq.com',
    'Nacho Bonafonte' => 'nacho.bonafontearruga@datadoghq.com'
  }
  
  s.source = {
    :http => "https://github.com/DataDog/dd-sdk-swift-testing/releases/download/#{s.version}/DatadogSDKTesting.zip",
    :sha256 => '60971055c7941a92f3b38769215111e1feb4da3b5a094da996e0aa262847c41b'
  }
  
  s.ios.deployment_target  = '13.0'
  s.osx.deployment_target  = '10.15'
  s.tvos.deployment_target = '13.0'
  
  s.vendored_frameworks    = 'DatadogSDKTesting.xcframework'
end
