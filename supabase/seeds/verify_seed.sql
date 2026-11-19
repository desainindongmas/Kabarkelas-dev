-- Verifikasi seed pilot
BEGIN;
SELECT 'students' AS item, count(*) FROM public.students WHERE local_student_no LIKE 'SIM-%'
UNION ALL SELECT 'classes', count(*) FROM public.school_classes WHERE name LIKE 'Kelas % Uji'
UNION ALL SELECT 'enrollments', count(*) FROM public.class_student_enrollments WHERE status='active'
UNION ALL SELECT 'subjects', count(*) FROM public.subjects WHERE code IN('MTK','IPA','BIN')
UNION ALL SELECT 'schedules', count(*) FROM public.lesson_schedules WHERE status='active'
UNION ALL SELECT 'announcements', count(*) FROM public.announcements WHERE status='published';
COMMIT;
ROLLBACK;
