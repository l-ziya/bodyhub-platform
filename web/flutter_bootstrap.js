{{flutter_js}}
{{flutter_build_config}}

// Keep the rendering engine with the application build. This prevents a
// browser or network policy from blocking the external CanvasKit CDN and
// leaving the Flutter view blank before the student application can start.
_flutter.loader.load({
  config: {
    canvasKitBaseUrl: 'canvaskit/',
  },
});
