# إصلاح SQL 42703 — ban_number

الخطأ سببه تشغيل ترقية V161 على قاعدة بيانات بها جدول `yamo_moderation_actions` قديم بدون عمود `ban_number`.

تم تعديل migration `202609160002_yamo_v161_unified_cup_live_ban.sql` بحيث:
- ينشئ sequence `yamo_ban_number_seq` إذا لم تكن موجودة.
- يضيف `ban_number` إذا كان مفقودًا.
- يضبط الـsequence بعد أعلى رقم موجود لتجنب التكرار.
- يملأ السجلات القديمة بأرقام تلقائية.
- يعيد إنشاء `get_yamo_session_guard_v161()` بعد تجهيز العمود.
- يحتفظ بإصلاح 42P13 للدالة `get_yamo_general_cup`.

شغّل ملف migration المصحح كاملًا من أوله.
