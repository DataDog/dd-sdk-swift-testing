Pod::Spec.new do |s|
  s.name          = 'DatadogSDKTesting'
  s.module_name   = 'DatadogSDKTesting'
  s.version       = '2.5.1-alpha2'
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
    :sha256 => 'f4d8ba0845c586e9b2cc69ac194e0be6b106e67645d9333e783f9c4d6b6830bb'
  }
  
  s.ios.deployment_target  = '13.0'
  s.osx.deployment_target  = '10.15'
  s.tvos.deployment_target = '13.0'
  
  s.vendored_frameworks    = 'DatadogSDKTesting.xcframework'
end
