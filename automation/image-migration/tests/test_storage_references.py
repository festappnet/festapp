import importlib.util
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from storage_references import inspect_value, rewrite_value, storage_identity


class References(unittest.TestCase):
    hosts = {'api.festapp.net', 'owned.supabase.co'}
    url = 'https://api.festapp.net/storage/v1/object/public/public-files/a%20b.png'
    target = 'https://img.festapp.net/assets/storage/owner/hash'

    def test_html_css_srcset_entities_and_nested_arrays(self):
        source = {'layout': [{'html': '<p>Keep &amp; content</p><img src="'+self.url+'" srcset="'+self.url+' 1x, '+self.url+' 2x"><div style="background:url(\''+self.url+'\')"></div>'}], 'font': 42}
        mapping = {('public-files','a b.png'): {'visibility':'public','url':self.target}}
        refs = list(inspect_value(source,self.hosts))
        self.assertEqual(len(refs),4)
        result = rewrite_value(source,self.hosts,mapping)
        self.assertEqual(result['font'],42)
        self.assertEqual(result['layout'][0]['html'], source['layout'][0]['html'].replace(self.url,self.target))

    def test_embedded_json_slash_and_unicode_escapes(self):
        mapping = {('public-files','a b.png'): {'visibility':'public','url':self.target}}
        for escaped in [self.url.replace('/',r'\/'),self.url.replace('/',r'\u002f')]:
            source = json.dumps({'html':'before '+escaped+' after'})
            # Already-decoded JSON values and JSON encoded inside text both
            # occur in application template/layout columns.
            value = json.loads(source)
            result = rewrite_value(value,self.hosts,mapping)
            self.assertEqual(len(list(inspect_value(value,self.hosts))),1)
            self.assertEqual(len(list(inspect_value(result,self.hosts))),0)

    def test_signed_tokens_are_not_identity_or_reported(self):
        signed = 'https://owned.supabase.co/storage/v1/object/sign/editor-files/a%2Fb.pdf?token=private-secret&amp;download=1'
        ref = list(inspect_value('<a href="'+signed+'">file</a>',self.hosts))[0]
        self.assertEqual(ref['identity'],{'bucket':'editor-files','key':'a/b.pdf','route':'sign'})
        self.assertNotIn('private-secret',json.dumps(ref))
        with self.assertRaisesRegex(ValueError,'private_reference'):
            rewrite_value(signed,self.hosts,{('editor-files','a/b.pdf'):{'visibility':'public','url':self.target}})

    def test_external_and_substring_hosts_are_untouched(self):
        urls = ['https://third-party.net/storage/v1/object/public/b/x','https://api.festapp.net.evil.test/storage/v1/object/public/b/x','https://third-party.net/?url=api.festapp.net/storage/v1/x']
        for url in urls:
            # An unrelated URL containing an owned host string is not owned.
            self.assertIsNone(storage_identity(url,self.hosts))
        self.assertEqual(rewrite_value(urls,self.hosts,{}),urls)
        embedded='https://third-party.net/?url='+self.url
        self.assertEqual(rewrite_value(embedded,self.hosts,{}),embedded)

    def test_protocol_relative_and_entity_quotes_preserve_fragment(self):
        source='<a href=&quot;'+self.url.removeprefix('https:')+'#page=3&quot;>Keep</a>'
        mapping={('public-files','a b.png'):{'visibility':'public','url':self.target}}
        self.assertEqual(rewrite_value(source,self.hosts,mapping),'<a href=&quot;'+self.target+'#page=3&quot;>Keep</a>')

    def test_rejects_traversal_unknown_routes_and_json_key_collisions(self):
        for path in ['object/public/b/%2e%2e/x','object/public/b/a//b','unknown/public/b/x']:
            with self.assertRaises(ValueError):
                storage_identity('https://api.festapp.net/storage/v1/'+path,self.hosts)
        mapping = {('public-files','a b.png'):{'visibility':'public','url':self.target}}
        with self.assertRaisesRegex(ValueError,'collision'):
            rewrite_value({self.url:1,self.target:2},self.hosts,mapping)


class Manifest(unittest.TestCase):
    def test_proven_null_ownership_is_retained_without_assigning_a_user(self):
        spec = importlib.util.spec_from_file_location('manifest',ROOT/'build-manifest.py')
        module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        source = {'id':'original-id','bucket_id':'editor-files','name':'private.pdf','version':'v1','owner':None,'owner_id':None,'metadata':{'size':3}}
        rows = [
            {'kind':'storage_security','rls':True,'client_roles':[{'name':name,'bypass':False,'superuser':False} for name in ('anon','authenticated')]},
            {'kind':'storage_policy','value':{'cmd':'SELECT','permissive':'PERMISSIVE','roles':['authenticated'],'qual':"((bucket_id = 'public-files'::text) AND can_delete_legacy_image_v1(name))"}},
            {'kind':'bucket','value':{'id':'editor-files','public':False}},
            {'kind':'object','value':source}]
        disk = [{'path':'stub/stub/editor-files/private.pdf/v1','size':3,'sha256':'a'*64}]
        result = module.build(rows,disk,{'api.festapp.net'},retain_ownerless=True)
        obj = result['objects'][0]
        self.assertTrue(result['summary']['ready_for_copy'])
        self.assertEqual(obj['source_storage_record'],source)
        self.assertEqual(obj['owners'],[])
        self.assertEqual(obj['visibility'],'private')
        self.assertEqual(obj['destination']['bucket'],'festapp-images-private')
        self.assertFalse(obj['custody']['application_write_grant'])
        rows.extend([
            {'kind':'relation','schema':'public','table':'occasions','primary_key':['id'],'relation_kind':'r','columns':[{'name':'id','generated':''},{'name':'description','generated':''}]},
            {'kind':'row','schema':'public','table':'occasions','value':{'id':63,'description':'https://api.festapp.net/storage/v1/object/public/public-files/missing.mbtiles'}}])
        partial = module.build(rows,disk,{'api.festapp.net'},retain_ownerless=True)
        self.assertTrue(partial['summary']['ready_for_copy'])
        self.assertFalse(partial['summary']['ready_for_reference_rewrite'])
        self.assertIn('reference_source_not_in_storage',partial['summary']['blockers'])
        # A new permissive private read cannot silently become service-only.
        rows.append({'kind':'storage_policy','value':{'cmd':'SELECT','permissive':'PERMISSIVE','roles':['authenticated'],'qual':'true'}})
        self.assertIn('ownership_unresolved',module.build(rows,disk,{'api.festapp.net'},retain_ownerless=True)['summary']['blockers'])

    def test_generated_fields_unowned_sources_and_orphans_fail_closed(self):
        spec = importlib.util.spec_from_file_location('manifest',ROOT/'build-manifest.py')
        module = importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
        rows = [
            {'kind':'bucket','value':{'id':'public-files','public':True}},
            {'kind':'object','value':{'bucket_id':'public-files','name':'x.png','version':'v1','metadata':{'size':3},'owner_id':None}},
            {'kind':'relation','schema':'public','table':'events','primary_key':['id'],'relation_kind':'r','columns':[{'name':'id','generated':''},{'name':'description','generated':''},{'name':'search_doc','generated':'s'}]},
            {'kind':'row','schema':'public','table':'events','value':{'id':1,'description':'https://api.festapp.net/storage/v1/object/public/public-files/x.png','search_doc':'https://api.festapp.net/storage/v1/object/public/public-files/lowercased-missing.png'}}]
        files = [{'path':'stub/stub/public-files/x.png/v1','size':3,'sha256':'a'*64},{'path':'unreferenced','size':4,'sha256':'b'*64}]
        result=module.build(rows,files,{'api.festapp.net'})
        self.assertEqual(result['summary']['current_fields'],1)
        self.assertNotIn('reference_source_not_in_storage',result['summary']['blockers'])
        self.assertFalse(result['summary']['ready_for_copy'])
        self.assertEqual(result['summary']['unreferenced_disk_files'],1)
        self.assertIn('ownership_unresolved',result['summary']['blockers'])
        retained=module.build(rows,files,{'api.festapp.net'},retain_orphan_bytes=True)
        self.assertNotIn('disk_orphan_disposition_required',retained['summary']['blockers'])
        self.assertEqual(retained['orphan_objects'][0]['source'],files[1])
        self.assertEqual(retained['orphan_objects'][0]['visibility'],'private')
        self.assertEqual(retained['orphan_objects'][0]['destination']['bucket'],'festapp-images-private')
        self.assertIsNone(retained['orphan_objects'][0]['source_storage_record'])
        self.assertEqual(retained['orphan_objects'][0]['owners'],[])


if __name__=='__main__': unittest.main()
