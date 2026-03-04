#error("""
c2pa_flutter requires Swift Package Manager. CocoaPods is not supported.

To fix this, enable SPM in your Flutter project:

  flutter config --enable-swift-package-manager

Then clean and rebuild:

  cd ios && rm -rf Pods Podfile.lock && cd ..
  flutter clean && flutter pub get && flutter build ios
""")
