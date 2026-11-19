BEGIN;

-- Opsi master (kelas & mapel) untuk form buat tugas/kuis
CREATE OR REPLACE FUNCTION app.g10_pilot_options(p_school uuid)
RETURNS TABLE(kind text,id uuid,name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY SELECT 'class'::text,c.id,c.name FROM public.school_classes c WHERE c.school_id=p_school ORDER BY c.name;
 RETURN QUERY SELECT 'subject'::text,s.id,s.name FROM public.subjects s WHERE s.school_id=p_school ORDER BY s.name;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_pilot_options(p_school uuid)
RETURNS TABLE(kind text,id uuid,name text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_pilot_options(p_school) $$;

-- Daftar siswa aktif untuk form nilai & P5 (staf saja)
CREATE OR REPLACE FUNCTION app.g10_pilot_students(p_school uuid)
RETURNS TABLE(student_id uuid,display_name text,local_student_no text,class_name text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path='' AS $$
BEGIN
 IF NOT app.pilot_can(p_school,ARRAY['teacher','principal','school_admin']) THEN
   RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 RETURN QUERY
 SELECT DISTINCT s.id,s.display_name,s.local_student_no,c.name
 FROM public.students s
 JOIN public.class_student_enrollments e ON e.school_id=s.school_id AND e.student_id=s.id AND e.status='active'
 JOIN public.school_classes c ON c.id=e.class_id AND c.school_id=e.school_id AND c.tenant_id=e.tenant_id
 WHERE s.school_id=p_school AND s.status='active'
 ORDER BY s.display_name;
END $$;

CREATE OR REPLACE FUNCTION public.kabarkelas_pilot_students(p_school uuid)
RETURNS TABLE(student_id uuid,display_name text,local_student_no text,class_name text)
LANGUAGE sql STABLE SECURITY INVOKER SET search_path='' AS $$ SELECT * FROM app.g10_pilot_students(p_school) $$;

REVOKE ALL ON FUNCTION app.g10_pilot_options(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.kabarkelas_pilot_options(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g10_pilot_options(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_pilot_options(uuid) TO authenticated;
REVOKE ALL ON FUNCTION app.g10_pilot_students(uuid) FROM PUBLIC,anon,authenticated;
REVOKE ALL ON FUNCTION public.kabarkelas_pilot_students(uuid) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g10_pilot_students(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.kabarkelas_pilot_students(uuid) TO authenticated;

COMMIT;
