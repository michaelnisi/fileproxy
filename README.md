# fileproxy

A URL proxy, or file download manager, for transient data, especially streamable media resources.

```swift
let url: URL = // Local or Remote Asset URL
let asset = AVAsset(url: url)
```

Motivated through [AVAsset](https://developer.apple.com/documentation/avfoundation/avasset), the objective of this package is to provide the URL of a local or remote asset, downloading the file in the background if it isn’t available locally yet.

## Background

Working with background downloads, keep this paragraph from [Apple’s documentation](https://developer.apple.com/documentation/foundation/url_loading_system/downloading_files_in_the_background) in mind:

> As a result, if your app starts a single background download, gets resumed when the download completes, and then starts a new download, it will greatly increase the delay. Instead, use a small number of background sessions — ideally just one — and use these sessions to start many download tasks at once. This allows the system to perform multiple downloads at once, and resume your app when they have completed.

## Testing

Testing and debugging apps with background downloading is tricky. Use logging and launch your app from the Home screen rather than running from Xcode. For debugging specific issues, attach to process from Xcode’s Debug menu.

This package is hardened by production. Additionally, you can run rudimentary tests with the [Package Manager](https://swift.org/package-manager/).

```
make test
```

## Install

📦 Add `https://github.com/michaelnisi/fileproxy` to your package dependencies.

## License

[MIT](https://raw.github.com/michaelnisi/fileproxy/master/LICENSE)
