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
