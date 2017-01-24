#
# Be sure to run `pod lib lint SQLiteWrapper.podspec' to ensure this is a
# valid spec before submitting.
#
# Any lines starting with a # are optional, but their use is encouraged
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html
#

Pod::Spec.new do |s|
  s.name             = 'SQLiteWrapper'
  s.version          = '0.1.2'
  s.summary          = 'A very lightweight SQLite wrapper with a SQL like API'

  s.description      = <<-DESC
A very lightweight SQLite wrapper with a SQL like API.
                       DESC

  s.homepage         = 'https://github.com/dave234/SQLiteWrapper'
  # s.screenshots     = 'www.example.com/screenshots_1', 'www.example.com/screenshots_2'
  s.license          = { :type => 'MIT', :file => 'LICENSE' }
  s.author           = { 'dave234' => 'dave234@users.noreply.github.com' }
  s.source           = { :git => 'https://github.com/dave234/SQLiteWrapper.git', :tag => s.version.to_s }
  # s.social_media_url = 'https://twitter.com/<TWITTER_USERNAME>'

  s.ios.deployment_target = '8.0'
  s.osx.deployment_target = '10.7'
  #s.platform = :osx
  #s.platform = :ios
  s.source_files = 'SQLiteWrapper/Classes/**/*'
 
  s.requires_arc = true 
  # s.resource_bundles = {
  #   'SQLiteWrapper' => ['SQLiteWrapper/Assets/*.png']
  # }

  # s.public_header_files = 'Pod/Classes/**/*.h'
  # s.frameworks = 'UIKit', 'MapKit'
  s.dependency 'sqlite3'
  #s.frameworks = 'sqlite3'
  #s.library = 'sqlite3'
end
