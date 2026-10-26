#!/usr/bin/env python3
"""Prepare the exact owner-approved five-reference disposition; no DB access."""
import argparse, copy, json, os
from html.parser import HTMLParser
from pathlib import Path

EXPECTED={('email_wrappers',20,'html'),('events',1390,'data'),
          ('events',1448,'data'),('occasions',376315,'data')}

def remove_images(text,urls):
 offsets=[0]
 for line in text.splitlines(keepends=True):offsets.append(offsets[-1]+len(line))
 spans=[];found=[]
 class Images(HTMLParser):
  def handle_starttag(self,tag,attrs):
   if tag!='img':return
   src=dict(attrs).get('src')
   if src not in urls:return
   line,column=self.getpos();start=offsets[line-1]+column
   spans.append((start,start+len(self.get_starttag_text())));found.append(src)
 Images().feed(text)
 if len(spans)!=2 or set(found)!=set(urls):raise ValueError('expected_exact_two_wrapper_images')
 for start,end in reversed(spans):text=text[:start]+text[end:]
 return text

def prepare(fields,inventory_sha256):
 if len(fields)!=4 or {(f['table'],f['id'],f['field']) for f in fields}!=EXPECTED:
  raise ValueError('unapproved_reference_scope')
 edits=[];all_urls=[]
 for f in fields:
  original=f['original'];urls=f['urls'];all_urls+=urls
  if f['table']=='email_wrappers':replacement=remove_images(original,urls)
  else:
   key='header_image' if f['table']=='events' else 'image'
   if len(urls)!=1 or not isinstance(original,dict) or original.get(key)!=urls[0]:
    raise ValueError('changed_reference_prestate')
   replacement=copy.deepcopy(original);del replacement[key]
  edits.append({'table':f['table'],'id':f['id'],'field':f['field'],'original':original,
                'replacement':replacement,'removed_images':2 if f['table']=='email_wrappers' else 1})
 if len(all_urls)!=5 or len(set(all_urls))!=5:raise ValueError('expected_exact_five_missing_urls')
 return {'approval':'five-broken-r2-references-20261018','removed_references':5,
         'inventory_sha256':inventory_sha256,'edits':edits}

def main():
 p=argparse.ArgumentParser();p.add_argument('--fields',type=Path,required=True);p.add_argument('--output',type=Path,required=True)
 p.add_argument('--owner-approved-five-missing-references',action='store_true',required=True);a=p.parse_args()
 value=json.loads(a.fields.read_bytes());bundle=prepare(value['fields'],value['inventory_sha256'])
 os.umask(0o077)
 with a.output.open('x') as out:json.dump(bundle,out,ensure_ascii=False,sort_keys=True)
 print('Prepared exactly five approved reference removals in four fields; no DB mutation')

if __name__=='__main__':main()
