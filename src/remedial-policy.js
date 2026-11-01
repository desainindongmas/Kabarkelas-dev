export function effectiveScore(original, attempts=[], policy={mode:'best_score'}) {
  const scores=[original,...attempts];
  if(scores.some(n=>typeof n!=='number'||!Number.isFinite(n)||n<0||n>100)) throw new RangeError('Nilai harus 0–100');
  if(!['best_score','latest_score','best_capped'].includes(policy.mode)) throw new Error('Kebijakan tidak dikenal');
  const best=Math.max(...scores);
  if(policy.mode==='best_score') return best;
  if(policy.mode==='latest_score') return scores.at(-1);
  if(typeof policy.cap!=='number'||policy.cap<0||policy.cap>100) throw new RangeError('Batas nilai tidak valid');
  return attempts.length?Math.max(original,Math.min(best,policy.cap)):original;
}
