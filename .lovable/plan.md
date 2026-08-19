## خطة إعادة هيكلة لوحة تحكم Yamo Chat

المهمة ضخمة (تنظيف + 7 أنظمة جديدة كبيرة + Migrations + اختبارات). سأقسّمها إلى مراحل قابلة للتنفيذ المتتابع، وأبدأ فورًا بعد موافقتك.

---

### المرحلة A — تنظيف البنية (بدون فقد بيانات)

**A1. القائمة الجانبية الجديدة (`src/lib/nav-config.ts`)**
إعادة كتابة كاملة بـ 23 عنصرًا رئيسيًا فقط مع دعم `children` للـ Submenus:

```text
1. الرئيسية               /dashboard
2. المستخدمون             /users
3. إدارة الوكالات         /agencies (+ hosts, bd, host-transfer-requests)
4. وكالات الشحن           /charging-agencies (Tabs داخلية)
5. الغرف                  /rooms
6. الرسائل والمكالمات     /messages
7. المنشورات              /posts
8. الاقتصاد والمحافظ      /economy (+ ledger, transactions, adjustments, disputes)
9. الشحن والسحب           /finance (+ packages, coin-prices, gateways, methods,
                                     recharge-requests, withdrawal-requests,
                                     pearl-prices, withdrawal-settings, reports)
10. الهدايا والمتجر والمقتنيات /store
11. الألعاب               /games
12. الفعاليات             /events
13. البنرات               /banners
14. جوائز تسجيل الدخول    /daily-login
15. الإشعارات             /notifications
16. البلاغات              /reports
17. مساعد الذكاء الاصطناعي /ai
18. التقارير والتحليلات   /analytics
19. الإعدادات             /settings
20. مسؤولو اللوحة         /admins
21. دعوات المسؤولين       /admins/invites
22. فحص الأمان            /security-check
23. سجل العمليات          /audit
```

**A2. تحديث `AppSidebar`** لدعم عناصر متداخلة (Collapsible groups) مع إبقاء الأيقونات في الوضع المطوي.

**A3. Redirects للروابط القديمة** (Route wrappers تُعيد التوجيه):
- `/charging-agents` → `/charging-agencies/agents`
- `/charging-coin-transfers` → `/charging-agencies/coin-transfers`
- `/charging-pearl-transfers` → `/charging-agencies/pearl-transfers`
- `/pearl-purchases` → `/charging-agencies/pearl-purchases`
- `/pearl-coin-exchanges` → `/charging-agencies/exchanges`
- `/wallet-adjustments` → `/economy/adjustments`
- `/charging-pricing` → `/charging-agencies/pricing`
- `/withdrawals` → `/finance/withdrawal-requests`
- `/store` (المكرر) → `/gifts`

**A4. تحويل صفحة `/charging-agencies` إلى Layout بـ Tabs** يعرض 9 صفحات فرعية (Overview / Agencies / Agents / Operations / Customers / Pricing / Payment Methods / Violations / Reports). الشاشات الموجودة تُنقل كما هي داخل الـ Tabs بدون فقدان كود.

**A5. تحويل `/economy` من Placeholder** إلى Layout بـ Tabs (Wallets / Ledger / Transactions / Adjustments / Disputes) — يستفيد من `wallet_ledger` و`wallets` الموجودة.

**A6. حذف `ModulePlaceholder`** من الصفحات التي أصبحت حقيقية، والإبقاء عليه فقط للصفحات التي لم تُبنَ بعد (مؤقتًا).

**A7. تحديث `Breadcrumbs`** لدعم المستويين (Section › Tab).

---

### المرحلة B — الأنظمة المفقودة (Migrations + UI)

سأنفّذها كـ Migration واحدة كبيرة ثم صفحات UI متتابعة.

**B1. باقات الشحن** — `/finance/packages`
جداول: `recharge_packages`, `recharge_package_prices`, `recharge_package_bonuses`, `recharge_package_targets`, `recharge_package_versions`
Enum حالة: `draft|review|published|paused|expired|archived`
صفحات: List, Create/Edit, Preview كما تظهر في التطبيق, Versions/Rollback.

**B2. أسعار الكوينز** — `/finance/coin-prices`
جداول: `coin_price_rules`, `coin_price_tiers`, `coin_price_versions`
شرائح كميات ديناميكية، فلترة حسب الدولة/البوابة/VIP/الوكالة.

**B3. بوابات الدفع** — `/finance/gateways`
جداول: `payment_gateways`, `payment_gateway_country_configs`, `payment_gateway_currencies`, `payment_webhooks`, `payment_transactions`, `payment_failures`
الأسرار في Backend Secrets فقط. زر Test Connection عبر Server Function.

**B4. وسائل الدفع** — `/finance/payment-methods`
جداول: `payment_methods`, `payment_method_accounts`
حقول حساسة مشفّرة، مرتبطة ببوابة.

**B5. أسعار اللؤلؤ/الورد** — `/finance/pearl-prices`
جداول: `pearl_price_rules`, `pearl_price_tiers`, `pearl_exchange_rates`, `pearl_price_versions`
(ملاحظة: `pearl_coin_exchange_rates` الحالي يبقى ويُدمج في العرض).

**B6. طلبات الشحن** — `/finance/recharge-requests`
جداول: `recharge_requests`, `recharge_request_events`, `recharge_receipts`
Enum: `created|pending_payment|paid|verifying|completed|failed|cancelled|refunded|disputed`
Idempotency + Webhook verify + Server-side wallet credit عبر `wallet_ledger`.

**B7. طلبات السحب وإعداداته** — `/finance/withdrawal-requests` + `/finance/withdrawal-settings`
جداول: `withdrawal_requests`, `withdrawal_reviews`, `withdrawal_methods`, `withdrawal_limits`, `withdrawal_fees`
حجز رصيد + مراجعة مزدوجة للعمليات الكبيرة.

**B8. Webhook Public Route**
`src/routes/api/public/payments/webhook.ts` — التحقق من التوقيع، Idempotency، credit عبر RPC.

**B9. الصلاحيات الجديدة**
إضافة صفوف في `permissions` وربطها بـ `super_admin`:
`recharge_packages.*`, `coin_prices.*`, `payment_gateways.*`, `payment_methods.*`, `pearl_prices.*`, `recharge_requests.*`, `withdrawal_requests.*`, `withdrawal_settings.*`, `finance.reports`.

---

### المرحلة C — تنظيف نهائي واختبار

- التأكد أن كل الوظائف "التنفيذية للوكيل" (شحن، تبديل، شراء لؤلؤ من مستخدم) في صفحات لوحة التحكم موسومة كـ **عرض/مراجعة/عكس فقط** — إزالة أي نموذج تنفيذ نيابة عن الوكيل من واجهة الإدارة. الأزرار المتبقية: تجميد / عكس / نزاع / ملاحظة إدارية.
- اختبار Playwright: كل الروابط تفتح، لا تكرار، لا Placeholder على العناصر الرئيسية، Redirects تعمل، Console نظيف.
- تقرير تسليم نهائي بالنقاط الـ20 المطلوبة.

---

### ملاحظات هامة

- **حجم العمل**: سيتطلب هذا 6-10 رسائل تنفيذية متتابعة (Migration واحدة ضخمة + ~25 ملف صفحة جديدة + إعادة كتابة nav/sidebar/breadcrumbs + redirects). لن أنفّذ كل شيء دفعة واحدة لأن Migrations تحتاج موافقتك بينها.
- **بيانات محفوظة**: لن أُسقط أي جدول مالي أو تاريخي؛ فقط أُضيف/أدمج واجهات.
- **وظائف الوكيل التنفيذية داخل تطبيق Android**: هذه خارج نطاق لوحة الويب الحالية (مشروع Android منفصل)؛ سأترك ملاحظة في `docs/` تشير إلى أن الصفحات المزالة من الويب تنتمي إلى `مركز وكالة الشحن` داخل تطبيق `com.blacksky.app`.

---

### ترتيب التنفيذ المقترح

1. **الآن**: المرحلة A كاملة (تنظيف + Redirects + Layout بـ Tabs) — بدون Migrations.
2. **بعدها**: Migration واحدة كبيرة تنشئ كل جداول المرحلة B + الصلاحيات.
3. **بعد الموافقة على Migration**: بناء صفحات B1→B8 على دفعتين.
4. **أخيرًا**: Webhook + اختبارات + تقرير التسليم.

هل أبدأ بالمرحلة A الآن؟ أم تريد تعديلًا على القائمة/الترتيب؟
