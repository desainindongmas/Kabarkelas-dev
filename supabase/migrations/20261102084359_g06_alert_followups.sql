BEGIN;
CREATE TABLE public.ews_followups(
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
 tenant_id uuid NOT NULL,
 school_id uuid NOT NULL,
 alert_id uuid NOT NULL,
 actor_user_id uuid NOT NULL REFERENCES public.users(id),
 previous_status text NOT NULL,
 new_status text NOT NULL CHECK(new_status IN ('under_review','resolved','dismissed','open')),
 note text NOT NULL CHECK(length(btrim(note)) BETWEEN 5 AND 1000),
 occurred_at timestamptz NOT NULL DEFAULT clock_timestamp(),
 FOREIGN KEY(tenant_id,school_id,alert_id) REFERENCES public.ews_alerts(tenant_id,school_id,id)
);
ALTER TABLE public.ews_followups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ews_followups FORCE ROW LEVEL SECURITY;
REVOKE ALL ON public.ews_followups FROM PUBLIC,anon,authenticated;
CREATE FUNCTION app.g06_update_alert(p_alert uuid,p_expected_status text,p_next_status text,p_note text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor(); v_alert public.ews_alerts%ROWTYPE; v_next text:=p_next_status;
BEGIN
 IF p_next_status NOT IN ('under_review','resolved','dismissed','open') OR p_next_status IS NULL OR p_expected_status IS NULL OR p_note IS NULL OR length(btrim(p_note)) NOT BETWEEN 5 AND 1000 THEN RAISE EXCEPTION 'Invalid review action' USING ERRCODE='22023'; END IF;
 SELECT * INTO v_alert FROM public.ews_alerts WHERE id=p_alert FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Alert unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.schools sc JOIN public.tenants t ON t.id=sc.tenant_id AND t.status='active' WHERE sc.id=v_alert.school_id AND sc.tenant_id=v_alert.tenant_id AND sc.status='active') THEN RAISE EXCEPTION 'Alert unavailable' USING ERRCODE='42501'; END IF;
 IF NOT (EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.tenant_id=v_alert.tenant_id AND m.school_id=v_alert.school_id AND m.role_code='principal' AND m.status='active')
 OR EXISTS(SELECT 1 FROM public.memberships m JOIN public.teacher_class_assignments tc ON tc.teacher_user_id=m.user_id AND tc.tenant_id=m.tenant_id AND tc.school_id=m.school_id AND tc.status='active' JOIN public.class_student_enrollments en ON en.class_id=tc.class_id AND en.student_id=v_alert.student_id AND en.tenant_id=tc.tenant_id AND en.school_id=tc.school_id AND en.status='active' WHERE m.user_id=v_actor AND m.tenant_id=v_alert.tenant_id AND m.school_id=v_alert.school_id AND m.role_code='teacher' AND m.status='active')) THEN RAISE EXCEPTION 'Alert unavailable' USING ERRCODE='42501'; END IF;
 IF v_alert.status<>p_expected_status THEN RAISE EXCEPTION 'Alert changed; reload' USING ERRCODE='40001'; END IF;
 IF NOT ((v_alert.status='open' AND v_next IN ('under_review','dismissed')) OR (v_alert.status='under_review' AND v_next IN ('resolved','dismissed')) OR (v_alert.status IN ('resolved','dismissed') AND v_next='open')) THEN RAISE EXCEPTION 'Invalid alert status transition' USING ERRCODE='22023'; END IF;
 UPDATE public.ews_alerts SET status=v_next WHERE id=p_alert;
 INSERT INTO public.ews_followups(tenant_id,school_id,alert_id,actor_user_id,previous_status,new_status,note) VALUES(v_alert.tenant_id,v_alert.school_id,p_alert,v_actor,v_alert.status,v_next,btrim(p_note));
 RETURN jsonb_build_object('alert_id',p_alert,'status',v_next);
END $$;
CREATE FUNCTION public.kabarkelas_ews_update_alert(p_alert uuid,p_expected_status text,p_next_status text,p_note text)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g06_update_alert(p_alert,p_expected_status,p_next_status,p_note) $$;
REVOKE ALL ON FUNCTION app.g06_update_alert(uuid,text,text,text),public.kabarkelas_ews_update_alert(uuid,text,text,text) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g06_update_alert(uuid,text,text,text),public.kabarkelas_ews_update_alert(uuid,text,text,text) TO authenticated;
COMMIT;