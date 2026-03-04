// swift-tools-version: 5.9

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
import PackageDescription

let package = Package(
    name: "c2pa_flutter",
    platforms: [
        .iOS(.v16),
        .macOS(.v14)
    ],
    products: [
        .library(name: "c2pa-flutter", targets: ["c2pa_flutter"])
    ],
    dependencies: [
        .package(url: "https://github.com/redaranj/c2pa-ios.git", exact: "0.0.9-beta.7")
    ],
    targets: [
        .target(
            name: "c2pa_flutter",
            dependencies: [
                .product(name: "C2PA", package: "c2pa-ios")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
