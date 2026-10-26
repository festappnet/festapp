import test from 'node:test';
import assert from 'node:assert/strict';
import {scannerReturnPath,safeScannerReturn} from '../../src/components/scan/scanner_navigation.js';
const origin='https://vstupenky.online';
const tickets='/PlesAKH2025-copy-ad8a55ba/reservations/tickets';
test('scanner returns to its ticket list after the scan secret is removed and after reload',()=>{
 const entries=new Map(),storage={getItem:k=>entries.get(k),setItem:(k,v)=>entries.set(k,v)};
 assert.equal(scannerReturnPath({location:{href:origin+'/scan/SECRET?returnTo='+encodeURIComponent(tickets)},storage}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'},storage}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan/settings'},returnTo:tickets,storage}),tickets);
});
test('scanner return paths reject other origins and scanner loops, and work without storage',()=>{
 for(const value of ['https://evil.invalid','//evil.invalid','/scan','/scan/settings','/login-qr'])assert.equal(safeScannerReturn(value,origin),null);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'},referrer:origin+tickets,storage:{getItem(){throw Error();},setItem(){throw Error();}}}),tickets);
 assert.equal(scannerReturnPath({location:{href:origin+'/scan'}}),'/');
});
