BEGIN;
CREATE FUNCTION app.g06_activate_rule(p_school uuid,p_key text,p_parameters jsonb)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();v_school public.schools%ROWTYPE; v_version integer; v_min integer;v_threshold numeric;
BEGIN
 SELECT * INTO v_school FROM public.schools WHERE id=p_school AND status='active' FOR UPDATE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.tenants t WHERE t.id=v_school.tenant_id AND t.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.tenant_id=v_school.tenant_id AND m.school_id=p_school AND m.role_code='principal' AND m.status='active') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 IF p_key NOT IN ('academic_low_average','attendance_unexcused') OR p_key IS NULL OR p_parameters IS NULL OR jsonb_typeof(p_parameters)<>'object' THEN RAISE EXCEPTION 'Invalid rule configuration' USING ERRCODE='22023'; END IF;
 IF p_key='academic_low_average' THEN
  IF NOT p_parameters ? 'threshold_percent' OR NOT p_parameters ? 'minimum_assessments' THEN RAISE EXCEPTION 'Missing rule parameters' USING ERRCODE='22023'; END IF;
  v_threshold := (p_parameters->>'threshold_percent')::numeric;v_min:=(p_parameters->>'minimum_assessments')::integer;
  IF v_threshold<0 OR v_threshold>100 OR v_min<2 OR v_min>50 THEN RAISE EXCEPTION 'Invalid academic threshold' USING ERRCODE='22023'; END IF;
 ELSE
  IF NOT p_parameters ? 'absent_threshold' OR NOT p_parameters ? 'lookback_days' THEN RAISE EXCEPTION 'Missing rule parameters' USING ERRCODE='22023'; END IF;
  v_min:=(p_parameters->>'absent_threshold')::integer;
  IF v_min<1 OR v_min>120 OR (p_parameters->>'lookback_days')::integer<1 OR (p_parameters->>'lookback_days')::integer>120 THEN RAISE EXCEPTION 'Invalid attendance threshold' USING ERRCODE='22023'; END IF;
 END IF;
 UPDATE public.ews_rules SET state='retired' WHERE school_id=p_school AND tenant_id=v_school.tenant_id AND rule_key=p_key AND state='active';
 SELECT coalesce(max(version),0)+1 INTO v_version FROM public.ews_rules WHERE school_id=p_school AND tenant_id=v_school.tenant_id AND rule_key=p_key;
 INSERT INTO public.ews_rules(tenant_id,school_id,rule_key,version,state,parameters) VALUES(v_school.tenant_id,p_school,p_key,v_version,'active',p_parameters);
 RETURN v_version;
END $$;
CREATE FUNCTION app.g06_scan_school(p_school uuid,p_window date DEFAULT CURRENT_DATE)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_actor uuid:=app.g05_actor();v_school public.schools%ROWTYPE;ru record;row_data record;v_created integer:=0;v_window text;v_key text;v_inserted integer;
BEGIN
 SELECT * INTO v_school FROM public.schools WHERE id=p_school AND status='active' FOR SHARE;
 IF NOT FOUND OR NOT EXISTS(SELECT 1 FROM public.tenants t WHERE t.id=v_school.tenant_id AND t.status='active') THEN RAISE EXCEPTION 'School unavailable' USING ERRCODE='42501'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.memberships m WHERE m.user_id=v_actor AND m.school_id=p_school AND m.tenant_id=v_school.tenant_id AND m.role_code='principal' AND m.status='active') THEN RAISE EXCEPTION 'Principal required' USING ERRCODE='42501'; END IF;
 IF p_window IS NULL OR p_window > CURRENT_DATE OR p_window < CURRENT_DATE - 120 THEN RAISE EXCEPTION 'Invalid scan date' USING ERRCODE='22023'; END IF;
 FOR ru IN SELECT * FROM public.ews_rules WHERE school_id=p_school AND tenant_id=v_school.tenant_id AND state='active' AND rule_key IN ('academic_low_average','attendance_unexcused') ORDER BY rule_key,version LOOP
   v_window:=to_char(p_window,'YYYY-MM-DD');
   IF ru.rule_key='academic_low_average' THEN
    FOR row_data IN SELECT * FROM app.g06_academic_preview(p_school,(ru.parameters->>'threshold_percent')::numeric,(ru.parameters->>'minimum_assessments')::integer) WHERE requires_review LOOP
     INSERT INTO public.ews_alerts(tenant_id,school_id,student_id,rule_id,window_key,severity,explanation)
     VALUES(v_school.tenant_id,p_school,row_data.student_id,ru.id,v_window,'review',
       format('Rata-rata %s%% dari %s penilaian final; butuh tinjauan guru',row_data.average_percent,row_data.assessment_count))
     ON CONFLICT(tenant_id,school_id,student_id,rule_id,window_key) DO NOTHING;
     GET DIAGNOSTICS v_inserted=ROW_COUNT;v_created:=v_created+v_inserted;
    END LOOP;
   ELSE
    FOR row_data IN SELECT * FROM app.g06_attendance_preview(p_school,p_window-((ru.parameters->>'lookback_days')::integer-1),p_window,(ru.parameters->>'absent_threshold')::integer) WHERE requires_review LOOP
     INSERT INTO public.ews_alerts(tenant_id,school_id,student_id,rule_id,window_key,severity,explanation)
     VALUES(v_school.tenant_id,p_school,row_data.student_id,ru.id,v_window,'review',
       format('%s ketidakhadiran tanpa keterangan dari %s sesi terbit; butuh tinjauan guru',row_data.unexcused_absences,row_data.session_count))
     ON CONFLICT(tenant_id,school_id,student_id,rule_id,window_key) DO NOTHING;
     GET DIAGNOSTICS v_inserted=ROW_COUNT;v_created:=v_created+v_inserted;
    END LOOP;
   END IF;
 END LOOP;
 RETURN jsonb_build_object('created',v_created,'window',v_window);
END $$;
CREATE FUNCTION public.kabarkelas_ews_activate_rule(p_school uuid,p_key text,p_parameters jsonb)
RETURNS integer LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g06_activate_rule(p_school,p_key,p_parameters) $$;
CREATE FUNCTION public.kabarkelas_ews_scan_school(p_school uuid,p_window date DEFAULT CURRENT_DATE)
RETURNS jsonb LANGUAGE sql SECURITY INVOKER SET search_path='' AS $$ SELECT app.g06_scan_school(p_school,p_window) $$;
REVOKE ALL ON FUNCTION app.g06_activate_rule(uuid,text,jsonb),app.g06_scan_school(uuid,date),public.kabarkelas_ews_activate_rule(uuid,text,jsonb),public.kabarkelas_ews_scan_school(uuid,date) FROM PUBLIC,anon,authenticated;
GRANT EXECUTE ON FUNCTION app.g06_activate_rule(uuid,text,jsonb),app.g06_scan_school(uuid,date),public.kabarkelas_ews_activate_rule(uuid,text,jsonb),public.kabarkelas_ews_scan_school(uuid,date) TO authenticated;
COMMIT;