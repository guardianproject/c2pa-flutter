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

// Widget tests for C2PA Flutter example app

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:c2pa_flutter_example/app.dart';

void main() {
  testWidgets('App renders without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const C2paExampleApp());

    // Verify that the app renders some expected content
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
