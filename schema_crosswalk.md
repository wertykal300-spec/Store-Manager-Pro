# Store Manager Pro — Schema Crosswalk Table
## جدول المقارنة الثلاثي الشامل بين C2 الفعلي و C2-R1 Supplemental و Canonical Schema

يوضح هذا الجدول المسار التاريخي الحقيقي لكل جدول بين:
- **مخطط C2 الأصلي الفعلي (42 جدولاً):** المخطط المعتمد في جولة المراجعة C2.
- **مخطط C2-R1 Supplemental:** محاولة الإغلاق التكميلية التي خلطت بعض الكيانات واحتفظت برقم 42 شكلياً.
- **Canonical Schema (55 جدولاً):** خط الأساس الإنتاجي المعتمد والنهائي للمشروع (Fresh Production Baseline).

---

### جدول المطابقة التاريخية الكاملة (Historical Schema Crosswalk)

| # | اسم الجدول في C2 الأصلي (42 جدولاً) | الحالة في C2-R1 Supplemental | الاسم والحالة في Canonical Schema | التصنيف الفعلي | سبب التغيير وموقع الوظيفة والأثر الهندسي |
| :---: | :--- | :--- | :--- | :---: | :--- |
| 1 | `stores` | موجود | `stores` | **KEPT** | تم الاحتفاظ به لتمثيل المتجر والموقع التجاري للمستأجر. |
| 2 | `warehouses` | موجود | `warehouses` | **KEPT** | تم الاحتفاظ به للمستودعات وربطها بالمتاجر والمخزون. |
| 3 | `users` | موجود | `users` | **KEPT** | تم الاحتفاظ به لإدارة المستخدمين والمصادقة. |
| 4 | `user_permissions` | استبدل بـ `permissions` و `role_permissions` | `permissions` + `role_permissions` + `user_roles` | **REPLACED / SPLIT** | في C2 كان جدول صلاحيات مبسط ومباشر. تم تفكيكه إلى نموذج RBAC معياري احترافي (أدوار، صلاحيات، وجداول وسيطة). |
| 5 | `user_sessions` | موجود | `user_sessions` | **KEPT** | تم الاحتفاظ به لتتبع الجلسات النشطة والرموز. |
| 6 | `registered_devices` | موجود | `registered_devices` | **KEPT** | تم الاحتفاظ به مع إضافة حقول المفتاح العام وحالة الإبطال والتسلسل `last_seq_num`. |
| 7 | `device_pairing_pins` | موجود | `device_pairing_pins` | **REPLACED** | استبدال التخزين البسيط برمز مشفر بـ `HMAC-SHA256` وسر خادمي وعداد محاولات ذري (3 محاولات). |
| 8 | `idempotent_requests` | غير موجود (تم إسقاطه شكلياً) | `idempotency_records` | **RENAMED / RESTORED** | أعيد إحياؤه تحت اسم `idempotency_records` لمنع تكرار الطلبات عبر LAN API مع نطاق `(tenant_id, device_id, client_request_id)`. |
| 9 | `units_of_measure` | موجود | `units_of_measure` | **KEPT** | تم الاحتفاظ به مع تقييد الأبعاد الفيزيائية وحماية بذرة `UOM_PIECE` بـ Trigger. |
| 10 | `unit_conversions` | موجود | `unit_conversions` | **KEPT** | تم تدعيمه بمنع التحويل عبر الأبعاد أو لنفس الوحدة أو التحويلات العكسية المتناقضة. |
| 11 | `categories` | موجود | `categories` | **KEPT** | تم الاحتفاظ به للتصنيف الشجري للمنتجات. |
| 12 | `products` | موجود | `products` | **KEPT** | تم ضبط `base_unit_id DEFAULT 'UOM_PIECE'` لدعم إنشاء المنتج بالاسم فقط دون أي حقل تقني إضافي. |
| 13 | `stock_items` | موجود | `stock_items` | **KEPT** | تم فرض قيد `Partial Unique Index` لضمان صنف مخزني بسيط واحد لكل منتج. |
| 14 | `attribute_definitions` | دمج في JSON | `product_variants.attributes_json` | **MERGED** | نقلت الخصائص المرنة إلى عمود `attributes_json` في المتغيرات لتسريع الاستعلامات وتجنب فرط التفرع. |
| 15 | `stock_item_attributes` | دمج في JSON | `product_variants.attributes_json` | **MERGED** | تم الدمج في متغير الصنف المخزني. |
| 16 | `inventory_balances` | موجود | `inventory_balances` | **KEPT** | تم تدعيمه بقيد `CHECK (on_hand_ticks >= reserved_ticks)` وحساب MAC. |
| 17 | `inventory_movements` | موجود | `inventory_movements` | **REPLACED** | تدعيمه بقيد `source_event_id TEXT UNIQUE NOT NULL` وحظر الحذف بـ Trigger. |
| 18 | `inventory_quotas` | موجود | `inventory_quotas` | **KEPT** | تدعيمه بحالات `LOST_DEVICE_EXPOSURE` وإلغاء الادعاءات التشفيرية الباطلة بالسحب الهوائي. |
| 19 | `parties` | فُصل إلى `customers` و `suppliers` | `customers` + `suppliers` | **SPLIT** | تم فصل جدول الأطراف العام إلى جدولين صريحين لضبط سقف الائتمان ومطابقة الأطراف المالية. |
| 20 | `financial_ledger` | غير موجود في C2-R1 | `party_ledger_entries` | **RENAMED / RESTORED** | أعيد باسم `party_ledger_entries` ليكون دفتر الأستاذ المساعد للعملاء والموردين. |
| 21 | `document_sequences` | غير موجود في C2-R1 | `document_sequences` | **RESTORED** | أعيد لضمان تسلسل ترقيم الفواتير والمستندات لكل سنة ومتجر دون فجوات. |
| 22 | `sales` | موجود | `sales` | **KEPT** | تم تدعيمه بحقول التوقيع الإلكتروني `device_signature`, `device_seq_num`, `request_hash`, و `local_operation_uuid`. |
| 23 | `sale_items` | موجود | `sale_items` | **KEPT** | تم تدعيمه بحقل `returned_quantity_ticks` وقيد `CHECK (returned_quantity_ticks <= quantity_ticks)`. |
| 24 | `sale_item_quota_allocations` | غير موجود في C2-R1 | `sale_item_quota_deductions` | **RENAMED / RESTORED** | أعيد بروابط تحقق صارمة وTrigger تحديث تلقائي لاستهلاك الحصص. |
| 25 | `sale_returns` | غير موجود في C2-R1 | `sale_returns` | **RESTORED** | أعيد لتوثيق مرتجعات المبيعات المستقلة برقم سند وتاريخ وربط بالفاتورة الأصلية. |
| 26 | `sale_return_items` | غير موجود في C2-R1 | `sale_return_items` | **RESTORED** | أعيد مع Trigger يمنع إرجاع كمية تزيد عن الكمية المباعة للبند الأصلي. |
| 27 | `purchases` | موجود | `purchases` | **KEPT** | تم تدعيمه بحالة الاستيفاء `fulfillment_status` وربطه بالاستلام الجزئي. |
| 28 | `purchase_items` | موجود | `purchase_items` | **KEPT** | تم تدعيمه بحقل `quantity_received_ticks` و `quantity_returned_ticks`. |
| 29 | `purchase_receipts` | غير موجود في C2-R1 | `purchase_receipts` | **RESTORED** | أعيد لتمكين إثبات الاستلام المخزني الجزئي والكامل للشحنات (GRN). |
| 30 | `purchase_receipt_items` | غير موجود في C2-R1 | `purchase_receipt_items` | **RESTORED** | أعيد مع Trigger يمنع استلام كمية تفوق الكمية المطلوبة في أمر الشراء. |
| 31 | `supplier_returns` | غير موجود في C2-R1 | `purchase_returns` | **RENAMED / RESTORED** | أعيد باسم `purchase_returns` لتوثيق رد البضاعة للموردين. |
| 32 | `supplier_return_items` | غير موجود في C2-R1 | `purchase_return_items` | **RENAMED / RESTORED** | أعيد مع Trigger يمنع إرجاع بضاعة لم يتم استلامها فعلياً. |
| 33 | `payments` | موجود | `payments` | **KEPT** | تم تدعيمه بحقول الدفعات العكسية `is_reversal`, `reversal_of_id UNIQUE`. |
| 34 | `payment_allocations` | موجود | `payment_allocations` | **REPLACED** | فرض الثبات التام (`Immutable`) والتحقق من `party_type` وسقف الديون. |
| 35 | `stock_audits` | أعيدت تسميته في C2-R1 | `inventory_adjustments` | **RENAMED** | رأس مستند تسوية الجرد المخزني والفروقات. |
| 36 | `stock_audit_items` | أعيدت تسميته في C2-R1 | `inventory_adjustment_lines` | **RENAMED** | بنود تسوية الجرد المخزني مع تحديد الكميات الفعلية والدفترية. |
| 37 | `cash_sessions` | أعيدت تسميته في C2-R1 | `cash_shifts` | **RENAMED** | ورديات الصندوق، مع إضافة قيد فريد يمنع وجود أكثر من وردية مفتوحة لنفس الصندوق. |
| 38 | `cash_movements` | غير موجود في C2-R1 | `cash_movements` | **RESTORED** | أعيد لتوثيق حركات النقدية (عهدة، سحب، مصروف، توريد) بـ `source_event_id UNIQUE`. |
| 39 | `expenses` | موجود | `expenses` | **KEPT** | تم الاحتفاظ به مع ربطه الاختياري بوردية الصندوق `shift_id`. |
| 40 | `audit_logs` | موجود | `audit_logs` | **KEPT** | تم تدعيمه بـ Triggers تمنع أي `UPDATE` أو `DELETE` عليه نهائياً. |
| 41 | `system_license` | غير موجود في C2-R1 | `app_licenses` | **RENAMED / RESTORED** | أعيد باسم `app_licenses` مع البصمة والتوقيع وفترة السماح وعدم قفل البيانات. |
| 42 | `backup_history` | غير موجود في C2-R1 | `backup_history` | **RESTORED** | أعيد لتوثيق عمليات النسخ الاحتياطي الساخن والتحقق من الـ SHA256 والاستعادة. |

---

### الجداول الإضافية المعيارية المستحدثة في Canonical Schema (13 جدولاً جديداً)

| # | اسم الجدول الجديد في Canonical | الغرض المعماري والمبرر الهندسي |
| :---: | :--- | :--- |
| 43 | `tenants` | عزل المستأجر المؤسسي لضمان قابلية التوسع وحماية حدود الترخيص. |
| 44 | `fiscal_years` | ضبط السنوات المالية ومنع ترحيل مستندات في فترات مقفلة أو خارج السنة. |
| 45 | `currencies` | تعريف العملة الأساسية (DZD) والعملات الأجنبية. |
| 46 | `exchange_rates` | حفظ أسعار الصرف بنسب كسرية دقيقة لحظة المعاملة. |
| 47 | `roles` | فصل الأدوار عن المستخدمين ضمن نموذج RBAC. |
| 48 | `permissions` | معجم الصلاحيات النظامية المتاحة في التطبيق. |
| 49 | `role_permissions` | جدول الربط بين الأدوار والصلاحيات. |
| 50 | `user_roles` | جدول الربط بين المستخدمين والأدوار. |
| 51 | `tax_rates` | نسب الضرائب والرسوم بنظام Basis Points الدقيق (19% = 1900 bps). |
| 52 | `product_variants` | تمثيل مستقل للمتغيرات (مقاس، لون، حجم) مع باركود وSKU خاص. |
| 53 | `price_lists` | تعريف قوائم الأسعار (تجزئة، جملة، تخفيضات). |
| 54 | `price_list_items` | أسعار الأصناف والمتغيرات داخل كل قائمة أسعار. |
| 55 | `customer_groups` | فئات العملاء مع نسب الخصم التلقائية الممنوحة لكل فئة. |
| 56 | `cash_registers` | تعريف أجهزة صناديق نقاط البيع الفعلية داخل المتجر لربط الورديات بها. |
| 57 | `expense_categories` | تصنيفات المصروفات العامة (إيجار، كهرباء، صيانة). |

*(المجموع النهائي في Canonical Schema هو 55 جدولاً بعد دمج وتصفية الكيانات المتطابقة)*.
