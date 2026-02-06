Pod::Spec.new do |s|
  s.name          = 'DatadogSDKTesting'
  s.module_name   = 'DatadogSDKTesting'
  s.version       = '2.6.5'
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
    :sha256 => 'd48154aadbcdb56fe1ff775790c44858f39d28c776adf3bd720dd59d60abbc95'
  }
  
  s.ios.deployment_target  = '12.0'
  s.osx.deployment_target  = '10.13'
  s.tvos.deployment_target = '12.0'
  
  s.vendored_frameworks    = 'DatadogSDKTesting.xcframework'
end
