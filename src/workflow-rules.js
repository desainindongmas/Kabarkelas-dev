// Presentation only. PostgreSQL independently authorizes every operation.
const transitions = Object.freeze({
  submit: { from: 'draft', to: 'submitted', role: 'teacher' },
  approve: { from: 'submitted', to: 'approved', role: 'principal' },
  publish: { from: 'approved', to: 'published', role: 'principal' },
});

export function canTransition(status, action, role, isSubmitter = false) {
  const rule = Object.hasOwn(transitions, action) && transitions[action];
  return Boolean(rule && rule.from === status && rule.role === role &&
    !(isSubmitter && action !== 'submit'));
}

export function nextStatus(status, action, role, isSubmitter = false) {
  if (!canTransition(status, action, role, isSubmitter)) throw new Error('Transisi tidak diizinkan.');
  return transitions[action].to;
}

export function availableActions(grade, role) {
  return ['submit', 'approve', 'publish'].filter(action =>
    grade.allowed_actions?.includes(action) && canTransition(grade.grade_status, action, role));
}
