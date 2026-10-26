export 'js_stub.dart'
    if (dart.library.html) 'js_web.dart' // dart2js web builds
    if (dart.library.js_interop) 'js_web.dart'; // dart2wasm web builds
