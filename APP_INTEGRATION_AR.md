# عقد ربط تطبيق Yamo Chat

هذه هي النقاط التي يستدعيها تطبيق Android بعد تسجيل الدخول إلى Supabase. لا يحتاج التطبيق إلى مفتاح `service_role` مطلقًا.

## عند فتح التطبيق

1. استدعاء `get_yamo_app_release('android', VERSION_CODE)`؛ إذا كانت `update_required=true` تظهر شاشة التحديث ولا يسمح بالتجاوز.
2. إرسال FCM token إلى `register_yamo_device_token(token,'android',deviceId,versionName)` بعد كل تسجيل دخول وكل تغيير للـtoken.
3. استدعاء `get_my_active_moderation()` وتطبيق حظر الرسائل أو الغرف أو المكالمات أو المنشورات حسب `action_type`.

## التحقق والدعم

- ترفع صور التحقق داخل bucket باسم `verification` في مسار يبدأ بـ UID المستخدم: `{uid}/...` ثم ينشأ سجل `yamo_verification_requests`.
- مرفقات الدعم داخل `support-attachments/{uid}/...` ثم ينشأ سجل `yamo_support_tickets`.
- التطبيق يقرأ السجلات الخاصة بالمستخدم فقط؛ RLS يمنع قراءة بيانات الآخرين.

## الصور والملفات

- صور البروفايل: `avatars/{uid}/...`.
- صور الغرف: `room-media/{uid}/...`.
- الهدايا والإطارات والدخلات: `catalog-assets/...` وتدار من المسؤولين.
- البنرات: `banners/...` وتدار من المسؤولين.

## حذف الحساب

يستدعي التطبيق `request_yamo_account_deletion(reason)`. بعد الموافقة ومرور سبعة أيام تنفذ المهمة المجدولة الحذف النهائي تلقائيًا.

## قاعدة الأمان

التطبيق يستخدم Publishable Key فقط. مفاتيح Firebase وService Role وبوابات الدفع تبقى في أسرار الخادم ولا توضع في APK.
