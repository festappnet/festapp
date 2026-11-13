import test from 'node:test';
import assert from 'node:assert/strict';
import {verifiedSessionAssurance, requireFreshStrongAuthentication} from '../src/auth/assurance.mjs';
import {authorizeApiAuthentication, operationAuthentication} from '../src/auth/operation-policy.mjs';
const now = Math.floor(Date.now()/1000), userId = '00000000-0000-4000-8000-000000000001';
const user = {id:userId, factors:[{status:'verified',factor_type:'totp'}]};
const claims = {sub:userId, iss:'https://backend.invalid/auth/v1', aud:'authenticated', role:'authenticated',
    aal:'aal2',session_id:'00000000-0000-4000-8000-000000000002',exp:now+3600,iat:now,
    amr:[{method:'password',timestamp:now},{method:'totp',timestamp:now-20}]};
const token = (patch={}) => 'header.'+Buffer.from(JSON.stringify({...claims,...patch})).toString('base64url')+'.signature';
const read = (patch={},actor=user) => verifiedSessionAssurance(token(patch),actor,'https://backend.invalid');
test('only GoTrue-verified session claims and a verified factor yield strong authentication evidence', () => {
    assert.equal(read().authTime, now-20);
    for (const patch of [{sub:'foreign'}, {iss:'https://foreign.invalid/auth/v1'}, {aud:'service_role'},
        {role:'service_role'}, {aal:'aal1'}, {session_id:null}, {exp:now-1}, {amr:[]},
        {amr:[{method:'password',timestamp:now}]}, {amr:[{method:'totp',timestamp:now+60}]}]) assert.equal(read(patch),null);
    assert.equal(read({}, {...user,factors:[]}),null);
    assert.equal(read({}, {...user,factors:[{status:'unverified',factor_type:'totp'}]}),null);
});
test('refresh iat never extends MFA freshness; subject and clock bounds fail closed', () => {
    const stale = read({iat:now,amr:[{method:'totp',timestamp:now-301}]});
    assert.throws(()=>requireFreshStrongAuthentication(stale,userId),/INSUFFICIENT_USER_AUTHENTICATION/);
    assert.throws(()=>requireFreshStrongAuthentication(read(),'foreign'),/INSUFFICIENT_USER_AUTHENTICATION/);
    requireFreshStrongAuthentication(read(),userId);
});
test('privileged API commands require registered DPoP + PAR and fresh strong backend authentication', () => {
    const context = {token:{jkt:'key'},client:{proofProfile:'dpop',requirePar:true},userId,authentication:read()};
    for (const id of ['banks.save','cards.refund.decide','payments.record','occasions.delete','profiles.roles']) {
        assert.equal(operationAuthentication(id).maxAgeSeconds,300);
        authorizeApiAuthentication(id,context);
        for (const patch of [{token:{}},{client:{proofProfile:'bearer',requirePar:true}},
            {client:{proofProfile:'dpop',requirePar:false}},{authentication:null}])
            assert.throws(()=>authorizeApiAuthentication(id,{...context,...patch}),/INSUFFICIENT_USER_AUTHENTICATION/);
    }
    authorizeApiAuthentication('events.save',{token:{},client:{},userId});
});
