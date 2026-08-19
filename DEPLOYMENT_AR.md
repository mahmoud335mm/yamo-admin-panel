# تشغيل لوحة تحكم Yamo Chat

## المتطلبات

- Node.js 20 أو أحدث.
- مشروع Supabase نفسه المستخدم داخل تطبيق Yamo Chat.
- تطبيق ملفات SQL داخل `supabase/migrations` بالترتيب من `001` إلى `016` دون تخطي أي ملف. الملف `015` يفعّل دورة الشحن اليدوي وحجز رصيد السحب الآمن، والملف `016` يكمل عقد حذف الحساب بين التطبيق واللوحة.
- إنشاء أول مسؤول باستخدام `supabase/BOOTSTRAP_FIRST_ADMIN.sql` مرة واحدة فقط.

## متغيرات الاستضافة

```env
VITE_SUPABASE_URL=https://YOUR_PROJECT.supabase.co
VITE_SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
SUPABASE_URL=https://YOUR_PROJECT.supabase.co
SUPABASE_PUBLISHABLE_KEY=YOUR_PUBLISHABLE_KEY
SUPABASE_SERVICE_ROLE_KEY=SERVER_ONLY_SECRET
CRON_SECRET=GENERATE_A_LONG_RANDOM_SECRET
FIREBASE_SERVICE_ACCOUNT_JSON={...}
```

لا يوضع `SUPABASE_SERVICE_ROLE_KEY` داخل متغير يبدأ بـ `VITE_`.

## البناء

```bash
npm ci
npm run build
```

خرج الإنتاج داخل `.output`. المشروع مضبوط حاليًا على Cloudflare/Nitro، ويمكن نشره على منصة تدعم Node أو Cloudflare Workers بعد إضافة المتغيرات السابقة.

## إنشاء أول مدير

1. أنشئ الحساب بالبريد من صفحة الدخول أو Supabase Auth.
2. عدّل البريد داخل `supabase/BOOTSTRAP_FIRST_ADMIN.sql`.
3. شغّل الملف مرة واحدة من SQL Editor.
4. كل المسؤولين التاليين تتم إضافتهم بالدعوات والصلاحيات من اللوحة.

## فحص بعد النشر

1. تسجيل الدخول بحساب غير إداري يجب أن يُرفض.
2. فتح الرئيسية والتأكد من ظهور مؤشرات Yamo.
3. فتح المستخدمين والمحافظ والغرف والهدايا.
4. تنفيذ إجراء على حساب تجريبي والتأكد من ظهوره في سجل العمليات.

## وظائف الخادم والجدولة

انشر مجلدات `supabase/functions` ثم أضف `CRON_SECRET` و`FIREBASE_SERVICE_ACCOUNT_JSON` إلى أسرار Supabase. اضبط جدولة HTTP مع header باسم `x-yamo-job-secret`:

- `dispatch-push-notifications`: كل دقيقة.
- `expire-moderation`: كل 15 دقيقة.
- `finalize-account-deletions`: مرة يوميًا.
- `health`: تستخدمه منصة المراقبة كل 5 دقائق.

## النسخ الاحتياطي

شغّل `scripts/backup-supabase.sh` يوميًا من خادم آمن بعد ضبط `SUPABASE_DB_URL`. يحتفظ افتراضيًا بآخر 14 يومًا مع SHA-256 لكل نسخة.

## ربط التطبيق

التعليمات الجاهزة موجودة في `APP_INTEGRATION_AR.md`. يلزم تطبيقها على نسخة Android سليمة لأن الملف المرفوع الحالي ناقص وغير قابل لفك الضغط بالكامل.
