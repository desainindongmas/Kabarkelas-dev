import test from 'node:test';
import assert from 'node:assert/strict';
import {effectiveScore} from '../src/remedial-policy.js';
test('nilai terbaik tidak turun saat remedial lebih rendah',()=>assert.equal(effectiveScore(65,[58],{mode:'best_score'}),65));
test('nilai terbaik meningkat saat remedial lebih tinggi',()=>assert.equal(effectiveScore(65,[86],{mode:'best_score'}),86));
test('kebijakan latest dapat menurunkan nilai',()=>assert.equal(effectiveScore(65,[58],{mode:'latest_score'}),58));
test('batas remedial tetap menjaga nilai awal',()=>{assert.equal(effectiveScore(65,[89],{mode:'best_capped',cap:75}),75);assert.equal(effectiveScore(88,[91],{mode:'best_capped',cap:75}),88);});
test('tanpa remedial tetap nilai awal',()=>assert.equal(effectiveScore(65,[],{mode:'best_score'}),65));
test('nilai tidak valid ditolak',()=>assert.throws(()=>effectiveScore(65,[NaN],{mode:'best_score'}),RangeError));
