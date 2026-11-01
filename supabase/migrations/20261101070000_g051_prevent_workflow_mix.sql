BEGIN;
-- Do not let the older per-grade principal workflow capture records already managed by G0.5.1.
CREATE FUNCTION app.g051_block_legacy_transitions()
RETURNS trigger LANGUAGE plpgsql SET search_path='' AS $$
BEGIN
 IF OLD.status IS DISTINCT FROM NEW.status
 AND EXISTS(SELECT 1 FROM public.assessment_attempts at WHERE at.grade_id=OLD.id) THEN
  RAISE EXCEPTION 'This assessment uses the teacher finalization workflow' USING ERRCODE='55000';
 END IF;
 RETURN NEW;
END $$;
CREATE TRIGGER g051_block_old_grade_workflow BEFORE UPDATE ON public.student_grades
 FOR EACH ROW EXECUTE FUNCTION app.g051_block_legacy_transitions();
REVOKE ALL ON FUNCTION app.g051_block_legacy_transitions() FROM PUBLIC,anon,authenticated;
COMMIT;
