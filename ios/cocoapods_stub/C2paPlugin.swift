/* 
This file is licensed to you under the Apache License, Version 2.0
(http://www.apache.org/licenses/LICENSE-2.0) or the MIT license
(http://opensource.org/licenses/MIT), at your option.

Unless required by applicable law or agreed to in writing, this software is
distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS OF
ANY KIND, either express or implied. See the LICENSE-MIT and LICENSE-APACHE
files for the specific language governing permissions and limitations under
each license.
*/

#error("""
c2pa_flutter requires Swift Package Manager. CocoaPods is not supported.

To fix this, enable SPM in your Flutter project:

  flutter config --enable-swift-package-manager

Then clean and rebuild:

  cd ios && rm -rf Pods Podfile.lock && cd ..
  flutter clean && flutter pub get && flutter build ios
""")
