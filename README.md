# fileproxy

A URL proxy, or file download manager, for transient data, especially streamable media resources.

```swift
let url: URL = // Local or Remote Asset URL
let asset = AVAsset(url: url)
```

Motivated through [AVAsset](https://developer.apple.com/documentation/avfoundation/avasset), the objective of this package is to provide the URL of a local or remote asset, downloading the file in the background if it isn’t available locally yet.
