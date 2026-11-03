import { assertEquals, assertThrows } from 'https://deno.land/std@0.224.0/assert/mod.ts';
import { documentLimits, boundDocumentInput, boundDocumentOutput } from './documentLimits.ts';
Deno.test('document output uses central limits and rejects missing or oversized work before base64',()=>{
 const limits=documentLimits({abuseLimits:{'document.input.bytes':10,'document.asset.bytes':20,'document.output.bytes':30,'document.output.pages':2}});
 assertEquals(limits.assetBytes,20);
 assertThrows(()=>documentLimits({}));
 assertThrows(()=>boundDocumentInput({text:'much too long'},limits.inputBytes));
 assertThrows(()=>boundDocumentOutput(new Uint8Array(31),1,limits));
 assertThrows(()=>boundDocumentOutput(new Uint8Array(10),3,limits));
 boundDocumentOutput(new Uint8Array(30),2,limits);
});
