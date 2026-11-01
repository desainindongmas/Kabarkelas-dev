CREATE OR REPLACE FUNCTION public.kabarkelas_grade_workflow_preview(p_grade_id uuid)
RETURNS jsonb LANGUAGE sql STABLE SECURITY INVOKER SET search_path=pg_catalog,public AS $$
 SELECT jsonb_build_object('grade_id',id,'status',status)
 FROM public.student_grades WHERE id=p_grade_id
$$; REVOKE ALL ON FUNCTION public.kabarkelas_grade_workflow_preview(uuid) FROM PUBLIC,anon;
