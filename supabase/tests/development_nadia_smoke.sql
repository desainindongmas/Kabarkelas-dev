-- Development-only smoke test using existing fictional identities. Always rollback.
BEGIN;
CREATE TEMP TABLE g05_smoke AS
SELECT g.id grade_id,g.school_id,g.revision,
 (SELECT u.auth_subject FROM public.users u JOIN public.memberships m ON m.user_id=u.id
  JOIN public.teacher_class_assignments tc ON tc.teacher_user_id=u.id AND tc.tenant_id=m.tenant_id AND tc.school_id=m.school_id
  WHERE m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='teacher' AND m.status='active' AND tc.status='active' AND tc.class_id=a.class_id LIMIT 1) teacher,
 (SELECT u.auth_subject FROM public.users u JOIN public.memberships m ON m.user_id=u.id WHERE m.tenant_id=g.tenant_id AND m.school_id=g.school_id AND m.role_code='principal' AND m.status='active' LIMIT 1) principal,
 (SELECT u.auth_subject FROM public.users u JOIN public.guardian_student_links l ON l.guardian_user_id=u.id JOIN public.memberships m ON m.user_id=u.id AND m.tenant_id=l.tenant_id AND m.school_id=l.school_id WHERE l.tenant_id=g.tenant_id AND l.school_id=g.school_id AND l.student_id=g.student_id AND l.verification_status='verified' AND m.role_code='guardian' AND m.status='active' LIMIT 1) guardian
FROM public.student_grades g JOIN public.students s ON s.id=g.student_id
JOIN public.assessments a ON a.id=g.assessment_id
JOIN public.subjects sub ON sub.id=a.subject_id
WHERE s.display_name='Nadia Simulasi' AND sub.name='Matematika (Simulasi)' AND g.score=82 AND g.status='draft';
GRANT SELECT ON g05_smoke TO authenticated;
CREATE TEMP TABLE g05_smoke_results(test_name text,passed boolean);
GRANT SELECT,INSERT ON g05_smoke_results TO authenticated;
CREATE FUNCTION pg_temp.smoke_ok(condition boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN
 IF condition IS DISTINCT FROM true THEN RAISE EXCEPTION 'FAIL: %',label; END IF;
 INSERT INTO g05_smoke_results VALUES(label,true);
END $$;
SELECT pg_temp.smoke_ok((SELECT count(*)=1 AND bool_and(teacher IS NOT NULL AND principal IS NOT NULL AND guardian IS NOT NULL AND teacher<>principal) FROM g05_smoke),'existing fictional actors found');
SELECT set_config('request.jwt.claim.sub',(SELECT guardian FROM g05_smoke),true);
SET LOCAL ROLE authenticated;
SELECT pg_temp.smoke_ok((SELECT count(*)=0 FROM public.kabarkelas_grade_workflow((SELECT school_id FROM g05_smoke)) WHERE grade_id=(SELECT grade_id FROM g05_smoke)),'Nadia draft hidden from linked guardian');
SELECT set_config('request.jwt.claim.sub',(SELECT teacher FROM g05_smoke),true);
SELECT pg_temp.smoke_ok((public.kabarkelas_transition_grade((SELECT grade_id FROM g05_smoke),'submit',(SELECT revision FROM g05_smoke))->>'status')='submitted','existing assigned teacher submits Nadia');
SELECT set_config('request.jwt.claim.sub',(SELECT principal FROM g05_smoke),true);
SELECT pg_temp.smoke_ok((public.kabarkelas_transition_grade((SELECT grade_id FROM g05_smoke),'approve',(SELECT revision+1 FROM g05_smoke))->>'status')='approved','existing principal approves Nadia');
SELECT set_config('request.jwt.claim.sub',(SELECT guardian FROM g05_smoke),true);
SELECT pg_temp.smoke_ok((SELECT count(*)=0 FROM public.kabarkelas_grade_workflow((SELECT school_id FROM g05_smoke)) WHERE grade_id=(SELECT grade_id FROM g05_smoke)),'Nadia approved hidden from linked guardian');
SELECT set_config('request.jwt.claim.sub',(SELECT principal FROM g05_smoke),true);
SELECT pg_temp.smoke_ok((public.kabarkelas_transition_grade((SELECT grade_id FROM g05_smoke),'publish',(SELECT revision+2 FROM g05_smoke))->>'status')='published','existing principal publishes Nadia');
SELECT set_config('request.jwt.claim.sub',(SELECT guardian FROM g05_smoke),true);
SELECT pg_temp.smoke_ok((SELECT score=82 AND grade_status='published' FROM public.kabarkelas_grade_workflow((SELECT school_id FROM g05_smoke)) WHERE grade_id=(SELECT grade_id FROM g05_smoke)),'linked guardian reads published Nadia score 82');
RESET ROLE;
SELECT pg_temp.smoke_ok((SELECT count(*)=3 FROM public.academic_workflow_events WHERE resource_id=(SELECT grade_id FROM g05_smoke)),'Nadia has three atomic audit events');
SELECT pg_temp.smoke_ok((SELECT count(*)=1 FROM public.academic_publication_snapshots WHERE resource_id=(SELECT grade_id FROM g05_smoke)),'Nadia has one immutable publication snapshot');
SELECT * FROM g05_smoke_results;
ROLLBACK;
