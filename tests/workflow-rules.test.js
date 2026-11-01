import test from 'node:test';
import assert from 'node:assert/strict';
import { canTransition,nextStatus } from '../src/workflow-rules.js';
test('urutan draf hingga terbit',()=>{
 assert.equal(nextStatus('draft','submit','teacher'),'submitted');
 assert.equal(nextStatus('submitted','approve','principal'),'approved');
 assert.equal(nextStatus('approved','publish','principal'),'published');
});
test('guru tidak menyetujui dan orang tua tidak menerbitkan',()=>{
 assert.equal(canTransition('submitted','approve','teacher'),false);
 assert.equal(canTransition('approved','publish','guardian'),false);
});
test('larangan melompati tahapan dan persetujuan diri',()=>{
 assert.equal(canTransition('draft','publish','principal'),false);
 assert.equal(canTransition('submitted','approve','principal',true),false);
});

test('aksi tidak dikenal dan status terminal ditolak',()=>{
 for(const action of ['toString','constructor','delete',null,undefined]) assert.equal(canTransition('draft',action,'teacher'),false);
 assert.equal(canTransition('published','publish','principal'),false);
 assert.throws(()=>nextStatus('draft','publish','principal'));
 assert.equal(canTransition('approved','publish','principal',true),false);
});
