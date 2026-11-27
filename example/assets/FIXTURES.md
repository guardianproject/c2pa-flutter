# Test fixtures

Copied from the c2pa-android test resources
(`test-shared/src/main/resources`, Apache-2.0 / MIT), which c2pa-swift
shares:

- `test_images/adobe_20220124_ci.jpg`: a JPEG signed by a third party, with
  ingredients and thumbnails.
- `test_images/video1.mp4`: an unsigned MP4 for BMFF signing.
- `test_certs/<alg>_certs.pem` and `test_certs/<alg>_private.key`: a test
  certificate chain and PKCS#8 private key for es384, es512, ps256, ps384,
  ps512 and ed25519.

The es256 pair (`test_es256_cert.pem`, `test_es256_key.pem`) and the unsigned
JPEG and PNG are this repository's own. None of the keys protect anything;
they exist only for tests.
