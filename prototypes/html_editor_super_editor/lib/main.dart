import 'package:flutter/material.dart';
import 'package:super_editor/super_editor.dart';
import 'package:super_editor_clipboard/super_editor_clipboard.dart';

import 'html_export.dart';
import 'image_component.dart';
import 'imported_images.dart';

void main() => runApp(const MaterialApp(home: EditorExperiment()));

class EditorExperiment extends StatefulWidget {
  const EditorExperiment({super.key});

  @override
  State<EditorExperiment> createState() => _EditorExperimentState();
}

class _EditorExperimentState extends State<EditorExperiment> {
  late final Editor _editor;
  late String _html;

  @override
  void initState() {
    super.initState();
    _editor = createDefaultDocumentEditor(
      document: MutableDocument(
        nodes: [
          ParagraphNode(
            id: 'intro',
            text: AttributedText(
              'Rufus Miller — obrázek načtený z lokální kopie',
            ),
          ),
          ImageNode(
            id: 'sample-image',
            imageUrl: sampleImageUrl,
            expectedBitmapSize: const ExpectedSize(251, 300),
          ),
          ParagraphNode(id: 'paste-here', text: AttributedText()),
        ],
      ),
    );
    _html = exportEditorHtml(_editor.document);
    _editor.document.addListener(_onDocumentChanged);
  }

  void _onDocumentChanged(DocumentChangeLog _) {
    setState(() => _html = exportEditorHtml(_editor.document));
  }

  @override
  void dispose() {
    _editor.document.removeListener(_onDocumentChanged);
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Super Editor: vložení HTML')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final editor = _pane(
            'Editor — klikni sem a vlož text z webu (Ctrl/Cmd+V)',
            SuperEditor(
              editor: _editor,
              componentBuilders: [
                const EditorImageComponentBuilder(),
                ...defaultComponentBuilders,
              ],
              keyboardActions: [
                pasteRichTextOnCmdCtrlV,
                ...defaultImeKeyboardActions,
              ],
            ),
          );
          final output = _pane(
            'HTML, které by se uložilo',
            SingleChildScrollView(
              child: SelectableText(
                _html,
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            ),
          );
          if (constraints.maxWidth < 850) {
            return Column(
              children: [
                Expanded(child: editor),
                Expanded(child: output),
              ],
            );
          }
          return Row(
            children: [
              Expanded(child: editor),
              Expanded(child: output),
            ],
          );
        },
      ),
    );
  }

  Widget _pane(String title, Widget child) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade400),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                title,
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: Padding(padding: const EdgeInsets.all(16), child: child),
            ),
          ],
        ),
      ),
    );
  }
}
