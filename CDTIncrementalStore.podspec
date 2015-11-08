# pod spec lint --allow-warnings --use-libraries
# pod trunk push --allow-warnings --use-libraries

license = <<EOT
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
EOT

Pod::Spec.new do |s|
  s.name         = "CDTIncrementalStore"
  s.version      = "0.2.0"
  s.summary      = "CDTIncrementalStore allows Core Data Frameworks to target CDTDatastore."
  s.description  = <<-DESC
                    CDTIncreamentalStore provides an Incremental Store
                    class that can be used as the persistent store
                    provider in a Core Data application. This
                    incremental store uses a CloudantSync datastore on
                    the device to persist any data that the
                    application stores to CoreData.
                   DESC
  s.homepage     = "http://github.com/jimix/CDTIncrementalStore"
  s.license      = {:type => 'Apache', :text => license}
  s.author       = { "IBM, Inc." => "jimix@pobox.com" }
  s.source       = { :git => "https://github.com/jimix/CDTIncrementalStore.git", :tag => s.version.to_s }

  s.ios.deployment_target = '6.0'
  s.osx.deployment_target = '10.8'
  s.requires_arc = true

  s.source_files = 'Classes/{common, ios, osx}/*.{h,m}'

  s.ios.exclude_files = 'Classes/osx'
  s.osx.exclude_files = 'Classes/ios'

  s.dependency 'CDTDatastore', '~> 1.0'
  s.frameworks =  'CoreData'
end
