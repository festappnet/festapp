"""Create a capture-only real editor host; never modify the package's source entry."""
import argparse
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('package',type=Path);a=p.parse_args()
source=(a.package/'example/lib/minimal.dart').read_text()
source="import 'dart:convert';\nimport 'dart:js_interop';\n"+source
source=source.replace('/// Run with', "@JS('window.captureLayoutDocument')\nexternal set captureLayoutDocument(JSString value);\n\n/// Run with",1)
source=source.replace('    } catch (error) {\n      _error', "      _controller!.addListener(() { captureLayoutDocument = jsonEncode(_controller!.document.toJson()).toJS; });\n    } catch (error) {\n      _error")
source=source.replace("title: 'Venue layout example',", "title: 'Editor plánku',\n    locale: const Locale(String.fromEnvironment('DEMO_LANGUAGE', defaultValue: 'cs')),")
source=source.replace('VenueLayoutTemplates.create(widget.templateId),', "VenueLayoutTemplates.create(widget.templateId, localize: const VenueLayoutLocalizations(Locale(String.fromEnvironment('DEMO_LANGUAGE', defaultValue: 'cs'))).text),")
source=source.replace("AppBar(title: Text('${widget.templateId} / ${widget.mode}'))", "AppBar(title: Text(const String.fromEnvironment('DEMO_LANGUAGE', defaultValue: 'cs') == 'cs' ? 'Plánek sálu' : 'Venue layout'))")
source=source.replace("VenueLayoutTemplates.create(widget.templateId, localize: const VenueLayoutLocalizations(Locale(String.fromEnvironment('DEMO_LANGUAGE', defaultValue: 'cs'))).text),", "captureInitialDocument(widget.templateId),")
source += '''
VenueLayoutDocument captureInitialDocument(String id) {
  final d=VenueLayoutTemplates.create(id, localize: const VenueLayoutLocalizations(Locale(String.fromEnvironment('DEMO_LANGUAGE', defaultValue:'cs'))).text);
  if (!const bool.fromEnvironment('DEMO_EMPTY')) return d;
  return d.copyWith(nodes:d.nodes.where((n)=>n.kind!='table'&&n.kind!='seat').toList(),attachments:[],selectionUnits:[]);
}
'''
target=a.package/'example/lib/landing_capture.dart';target.write_text(source);print(target)
