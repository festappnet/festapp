/// Both the downloadable kit (/flutter/) and project Pages host the preview
/// beside the editor, without assuming the site is deployed at the origin root.
Uri previewLocation(Uri editor) {
  final directory = editor.resolve('.');
  return directory.resolve(
    directory.path.endsWith('/flutter/') ? '../js/demo/' : 'js/demo/',
  );
}
