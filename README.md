# fileproxy

A URL proxy, or file download manager, for transient data, especially streamable media resources.

```swift
let url: URL = // Local or Remote Asset URL
let asset = AVAsset(url: url)
```

Motivated through [AVAsset](https://developer.apple.com/documentation/avfoundation/avasset), the objective of this package is to provide the URL of a local or remote asset, downloading the file in the background if it isn’t available locally yet.

## Testing

Using it in production, I know it works. I hope to add more tests ✌️
For now you can run rudimentary tests with the [Package Manager](https://swift.org/package-manager/).

```
make test
```

Testing within Xcode, you’d have to start the server manually first.

```
node server
```

## License

[MIT](https://raw.github.com/michaelnisi/fileproxy/master/LICENSE)
