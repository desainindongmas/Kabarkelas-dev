BEGIN;
CREATE FUNCTION app.g051_report_audit()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$
DECLARE v_user uuid; v_action text; v_from text;
BEGIN
 IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authenticated actor required' USING ERRCODE='28000'; END IF;
 SELECT id INTO v_user FROM public.users WHERE auth_subject=auth.uid()::text;
 IF v_user IS NULL THEN RAISE EXCEPTION 'Unknown actor' USING ERRCODE='42501'; END IF;
 IF TG_OP='INSERT' THEN v_action:='create'; v_from:=NULL;
 ELSE
  IF NEW.status=OLD.status THEN RETURN NEW; END IF;
  v_from:=OLD.status;
  v_action:=CASE NEW.status WHEN 'teacher_finalized' THEN 'submit' WHEN 'homeroom_reviewed' THEN 'approve' WHEN 'principal_signed' THEN 'approve' WHEN 'released' THEN 'publish' ELSE 'edit' END;
 END IF;
 INSERT INTO public.academic_workflow_events(tenant_id,school_id,resource_type,resource_id,actor_user_id,actor_auth_subject,from_state,to_state,action,request_id)
 VALUES(NEW.tenant_id,NEW.school_id,'report_card',NEW.id,v_user,auth.uid(),v_from,NEW.status,v_action,gen_random_uuid());
 RETURN NEW;
END $$;
CREATE TRIGGER g051_audit_report_create AFTER INSERT ON public.school_report_reviews FOR EACH ROW EXECUTE FUNCTION app.g051_report_audit();
CREATE TRIGGER g051_audit_report_transition AFTER UPDATE ON public.school_report_reviews FOR EACH ROW EXECUTE FUNCTION app.g051_report_audit();
REVOKE ALL ON FUNCTION app.g051_report_audit() FROM PUBLIC,anon,authenticated;
COMMIT;
