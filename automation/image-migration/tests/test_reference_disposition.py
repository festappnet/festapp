import importlib.util,json,os,sys,unittest
from pathlib import Path

HERE=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(HERE))
spec=importlib.util.spec_from_file_location('disposition',HERE/'prepare-approved-reference-cleanup.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

def fixture():
 urls=['https://img.festapp.net/images/missing'+str(i)+'.png' for i in range(5)]
 return [
  {'table':'email_wrappers','id':20,'field':'html','urls':urls[:2],
   'original':'<p>Keep &amp; text</p><img src="'+urls[0]+'"/><b>Keep</b><img src="'+urls[1]+'"><img src="https://external.test/keep.png">'},
  {'table':'events','id':1390,'field':'data','urls':[urls[2]],'original':{'header_image':urls[2],'keep':['text',42]}},
  {'table':'events','id':1448,'field':'data','urls':[urls[3]],'original':{'header_image':urls[3],'keep':True}},
  {'table':'occasions','id':376315,'field':'data','urls':[urls[4]],'original':{'image':urls[4],'keep':{'nested':'value'}}},
 ]

class Preparation(unittest.TestCase):
 def test_immutable_replay_and_audit_are_history_but_templates_are_current(self):
  spec=importlib.util.spec_from_file_location('manifest',HERE/'build-manifest.py')
  manifest=importlib.util.module_from_spec(spec);spec.loader.exec_module(manifest)
  rows=[]
  for table,field in [('client_commit_items','safe_label'),('client_mutation_receipts','response'),('email_wrappers','html')]:
   rows += [{'kind':'relation','schema':'public','table':table,'primary_key':['id'],'relation_kind':'r',
             'columns':[{'name':'id','generated':''},{'name':field,'generated':''}]},
            {'kind':'row','schema':'public','table':table,'value':{'id':1,field:'https://api.festapp.net/storage/v1/object/public/public-files/gone.png'}}]
  result=manifest.build(rows,[],{'api.festapp.net'},retain_ownerless=True)
  kinds={f['table']:f['classification'] for f in result['fields']}
  self.assertEqual(kinds,{'client_commit_items':'history','client_mutation_receipts':'history','email_wrappers':'current'})
  self.assertEqual(result['summary']['current_references'],1)
  self.assertFalse(result['summary']['ready_for_reference_rewrite'])
 def test_only_approved_images_and_properties_are_removed(self):
  fields=fixture();before=json.dumps(fields);b=m.prepare(fields,'a'*64)
  self.assertEqual(json.dumps(fields),before)
  self.assertEqual(b['edits'][0]['replacement'],'<p>Keep &amp; text</p><b>Keep</b><img src="https://external.test/keep.png">')
  self.assertEqual(b['edits'][1]['replacement'],{'keep':['text',42]})
  self.assertEqual(b['edits'][3]['replacement'],{'keep':{'nested':'value'}})
 def test_changed_scope_or_missing_image_refuses_preparation(self):
  fields=fixture();fields[1]['id']=999
  with self.assertRaisesRegex(ValueError,'scope'):m.prepare(fields,'a'*64)
  fields=fixture();fields[0]['original']=fields[0]['original'].replace('<img','<a',1)
  with self.assertRaisesRegex(ValueError,'two_wrapper'):m.prepare(fields,'a'*64)

if __name__=='__main__':unittest.main()
