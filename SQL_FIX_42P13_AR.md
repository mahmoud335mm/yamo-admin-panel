# إصلاح خطأ SQL 42P13

تم تعديل migration `202609160002_yamo_v161_unified_cup_live_ban.sql` ليحذف توقيع الدالة القديمة:

`public.get_yamo_general_cup(text,text,integer)`

قبل إعادة إنشائها بنوع الإرجاع الجديد. هذا يمنع خطأ:
`cannot change return type of existing function`.

إذا كان تنفيذ الملف السابق فشل داخل `BEGIN`، أعد تشغيل الملف المصحح كاملًا من البداية.
