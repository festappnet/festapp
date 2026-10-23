"""Contract regression tests, not approval of any real product footage."""
import copy,importlib.util,json,sys,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2];sys.path.insert(0,str(ROOT/'automation/landing_capture'))
import scenario_contract as s
import encode_revision as encoder
class CaptureParityTests(unittest.TestCase):
 def fixture(self,clip='layout-build'):
  c=s.contract(clip);return {'fixture':c['fixture'],'geometry':{'canvas':[2100,1800],'nodePositions':[[1,10,20],[2,30,40]]},'data':c.get('data',{}),'before':c['before']}
 def job(self,locale='cs',clip='layout-build'):return s.prepare(clip,locale,self.fixture(clip),'a'*64)
 def reviewed(self,locale,clip='layout-build'):
  j=self.job(locale,clip);c=j['contract'];r=s.start_receipt(j,{'viewport':c['camera']['viewport'],'deviceScaleFactor':1,'locale':locale,'theme':'light'})
  for b in c['beats']:s.beat(r,b)
  s.finish(r);r.update(status='reviewed',after=copy.deepcopy(c['after']),edit=copy.deepcopy(c['edit']),exports={'desktop':c['camera']['desktop'],'mobile':c['camera']['mobile']},takeSha256=('b' if locale=='cs' else 'c')*64,exportSha256={'desktop':('d' if locale=='cs' else 'e')*64,'mobile':('f' if locale=='cs' else 'a')*64},checks={key:True for key in ('actualReadback','firstMiddleLastFrames','fullDecode','fullPlayback')});return r
 def test_locale_changes_only_text_not_camera_or_geometry(self):
  cs,en=self.job(),self.job('en');self.assertEqual(cs['scenarioSha256'],en['scenarioSha256']);self.assertEqual(cs['contract'],en['contract']);self.assertNotEqual(cs['text'],en['text'])
 def test_changing_prices_is_not_localization(self):
  f=self.fixture('form-build');f['data']=copy.deepcopy(f['data']);f['data']['baseAdmissionPrice']=350
  with self.assertRaisesRegex(ValueError,'numeric/business'):s.prepare('form-build','en',f,'a'*64)
 def test_wrong_initial_inventory_rejected(self):
  f=self.fixture();f['before']={'tables':6,'seats':38}
  with self.assertRaisesRegex(ValueError,'preconditions'):s.prepare('layout-build','en',f,'a'*64)
 def test_capture_cannot_auto_compensate_wrong_camera(self):
  with self.assertRaisesRegex(ValueError,'Camera/viewport'):s.start_receipt(self.job(),{'viewport':[1280,960],'deviceScaleFactor':1,'locale':'cs','theme':'light'})
 def test_wrong_locale_or_dark_theme_rejected(self):
  for locale,theme in [('en','light'),('cs','dark')]:
   with self.assertRaisesRegex(ValueError,'locale/theme'):s.start_receipt(self.job(),{'viewport':[1440,960],'deviceScaleFactor':1,'locale':locale,'theme':theme})
 def test_missing_and_reordered_beats_fail_closed(self):
  r=s.start_receipt(self.job(),{'viewport':[1440,960],'deviceScaleFactor':1,'locale':'cs','theme':'light'})
  with self.assertRaisesRegex(ValueError,'reordered'):s.beat(r,'add-seat-two')
  with self.assertRaisesRegex(ValueError,'Incomplete'):s.finish(r)
 def test_stale_job_cannot_be_recorded(self):
  j=self.job();j['contract']['camera']['crop']=[1280,844,0,112]
  with self.assertRaisesRegex(ValueError,'modified'):s.start_receipt(j,{})
 def test_reviewed_independent_locale_pair(self):self.assertEqual(s.pair(self.reviewed('cs'),self.reviewed('en'))['status'],'matched-inputs-and-reviewed-outcomes')
 def test_pair_rejects_different_geometry_source_or_numeric_data(self):
  for field in ('sourceTreeSha256','fixtureGeometrySha256','fixtureDataSha256'):
   en=self.reviewed('en');en[field]='d'*64
   with self.assertRaisesRegex(ValueError,field):s.pair(self.reviewed('cs'),en)
 def test_relabeling_same_video_is_not_an_english_take(self):
  cs,en=self.reviewed('cs'),self.reviewed('en');en['takeSha256']=cs['takeSha256']
  with self.assertRaisesRegex(ValueError,'independently'):s.pair(cs,en)
 def test_wrong_outcome_or_missing_visual_review_is_not_a_pass(self):
  for edit in (lambda r:r['after'].update(seats=36),lambda r:r['checks'].update(firstMiddleLastFrames=False)):
   en=copy.deepcopy(self.reviewed('en'));edit(en)
   with self.assertRaises(ValueError):s.pair(self.reviewed('cs'),en)
 def test_different_edit_or_phone_presentation_is_not_a_match(self):
  en=self.reviewed('en');en['edit']['speed']=1.5
  with self.assertRaisesRegex(ValueError,'speed'):s.pair(self.reviewed('cs'),en)
  en=self.reviewed('en');en['exports']['mobile']=[720,900]
  with self.assertRaisesRegex(ValueError,'framing'):s.pair(self.reviewed('cs'),en)
 def test_existing_english_assets_are_not_retroactively_certified(self):
  report=s.audit(s.read(ROOT/'automation/release/organizers/clips.en.json'));self.assertFalse(report['readyForOneToOnePublication']);self.assertEqual(len(report['clips']),8);self.assertTrue(any(not r['dimensionsMatch'] for r in report['clips']))
 def test_encoder_rejects_per_locale_crop_override(self):
  r=self.reviewed('cs');r['status']='recorded-needs-outcome-and-visual-review'
  with tempfile.TemporaryDirectory() as t:
   path=Path(t);s.write(path/'scenario-receipt.json',r)
   with self.assertRaisesRegex(ValueError,'override'):encoder.scenario_settings(path,'layout-build','1280:844:0:112',None,None)
   crop,desktop,mobile,_=encoder.scenario_settings(path,'layout-build',None,None,None);self.assertEqual((crop,desktop,mobile),('1128:780:0:112','1140:792','820:792'))
 def test_phone_chapter_cannot_silently_use_generic_letterbox(self):
  j=s.prepare('check-in','cs',self.fixture('check-in'),'a'*64);r={**j,'status':'recorded-needs-outcome-and-visual-review'}
  with tempfile.TemporaryDirectory() as t:
   path=Path(t);s.write(path/'scenario-receipt.json',r)
   with self.assertRaisesRegex(ValueError,'phone/multi-cue'):encoder.scenario_settings(path,'check-in',None,None,None)
 def aligned_manifest(self):
  m=s.read(ROOT/'automation/release/organizers/clips.en.json')
  for c in m['clips']:
   if c['id'] in s.read(s.SPEC)['clips']:
    camera=s.contract(c['id'])['camera'];c.update(width=camera['desktop'][0],height=camera['desktop'][1],mobileWidth=camera['mobile'][0],mobileHeight=camera['mobile'][1])
  return m
 def test_publication_requires_a_receipt_for_every_rendered_clip(self):
  with tempfile.TemporaryDirectory() as t:
   with self.assertRaisesRegex(ValueError,'Missing paired'):s.verify_pairs(t,self.aligned_manifest())
   for key in s.read(s.SPEC)['clips']:
    for locale in ('cs','en'):s.write(Path(t)/(key+'.'+locale+'.json'),self.reviewed(locale,key))
   self.assertEqual(len(s.verify_pairs(t,self.aligned_manifest())),8)
 def test_valid_receipts_do_not_excuse_different_published_dimensions(self):
  with tempfile.TemporaryDirectory() as t:
   with self.assertRaisesRegex(ValueError,'Published framing'):s.verify_pairs(t,s.read(ROOT/'automation/release/organizers/clips.en.json'))
 def test_encoder_requires_hashes_bound_to_actual_export_files(self):
  en=self.reviewed('en');en.pop('exportSha256')
  with self.assertRaisesRegex(ValueError,'export hashes'):s.pair(self.reviewed('cs'),en)
if __name__=='__main__':unittest.main()
