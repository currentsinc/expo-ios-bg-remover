# Expo iOS Bg Remover

[![runs with expo](https://img.shields.io/badge/Runs%20with%20Expo-4630EB.svg?style=flat-square&logo=EXPO&labelColor=f3f3f3&logoColor=000)](https://expo.io/)

An [Expo module](https://docs.expo.dev/modules/overview/) to remove the background from an image using the [Image Background Removal API](https://developer.apple.com/documentation/vision/vninstancemaskobservation) introduced in iOS 17.

## Caveats
- This module only works on iOS 17 and above.
- This will not work in the Expo Go app or the iOS simulator. You must build your app and run it on a physical device.
- The image must be a URI to a local file on the device.