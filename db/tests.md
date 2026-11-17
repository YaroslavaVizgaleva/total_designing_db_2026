# Протокол для самопроверки

Протокол заполнен по результатам реального прогона: чистый контейнер PostgreSQL, восстановление `foodexpress_vizgaleva.backup`, применение `db/schema/grants.sql`, все проверки под `inspector`.

## Окружение

| Параметр | Значение |
|---|---|
| PostgreSQL version | `PostgreSQL 17.12 (Debian 17.12-1.pgdg13+1) on x86_64-pc-linux-gnu, compiled by gcc (Debian 14.2.0-19) 14.2.0, 64-bit` |
| Дата проверки | 2026-11-16 |
| Схема | `vizgaleva_food` |
| Роль-аудитор | `inspector` |

Все проверки — под `inspector`, если не указано иное.

Отличия запросов от шаблона (под нашу схему):
- `add_product`: параметр названия блюда — `p_product_name`; параметра рейтинга нет (у нового блюда `rating = NULL` по BR-9.7). Подзапросы в аргументах `CALL` PostgreSQL не разрешает (`cannot use subquery in CALL argument`), поэтому id ресторана и категории передаются через переменные psql (`\gset`).
- Месяц для зарплаты (C.8) — по `delivery_timestamp` (момент доставки), так же как в `courier_salary`.
- Рейтинг (D.14) — с округлением до 1 знака: `rating` имеет тип `numeric(2,1)`.

---

## A. Подготовка

### A.1. Восстановление бэкапа

```bash
createdb -U postgres food
psql -U postgres -d food -c 'CREATE SCHEMA exts; CREATE EXTENSION "uuid-ossp" SCHEMA exts;'  # exts есть в окружении по BR-13.3
pg_restore -U postgres -d food --exit-on-error foodexpress_vizgaleva.backup
psql -U postgres -d food -v ON_ERROR_STOP=1 -f db/schema/grants.sql
```

Ожидается: без ошибок.
Факт: `pg_restore` exit=0; `grants.sql` exit=0, `NOTICE: Права пользователя inspector выданы и проверены`.
Вердикт: OK

### A.2. Переключение на inspector

```sql
SET ROLE inspector;
SET search_path TO vizgaleva_food, exts;
SELECT current_user;
```

Ожидается: `inspector`.
Факт: `inspector`
Вердикт: OK

---

## B. FOOD-101: Структура схемы

### B.1. Схема существует

```sql
SELECT schema_name FROM information_schema.schemata
WHERE schema_name LIKE '%_food';
```

Ожидается: `vizgaleva_food`.
Факт: `vizgaleva_food`
Вердикт: OK

### B.2. Схема `exts` с `uuid-ossp`

```sql
SELECT extname, extnamespace::regnamespace AS schema
FROM pg_extension WHERE extname = 'uuid-ossp';
```

Ожидается: `uuid-ossp`, схема `exts`.
Факт: `uuid-ossp | exts`
Вердикт: OK

### B.3. Все 12 исходных таблиц + N после нормализации

```sql
SELECT table_name FROM information_schema.tables
WHERE table_schema = 'vizgaleva_food'
ORDER BY table_name;
```

Ожидается: 12 таблиц + N.
Факт: `address`, `client`, `client_address`, `courier`, `courier_pay`, `how_much_money`, `order`, `order_structure`, `payment`, `product`, `product_category`, `restaurant`, `review` — 12 таблиц из ERD (N = 0, новых таблиц не добавлялось) + представление `how_much_money` (FOOD-108).
Вердикт: OK

### B.4. Все PK — `uuid`

```sql
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'vizgaleva_food'
  AND column_name LIKE '%_id'
  AND data_type != 'uuid';
```

Ожидается: пусто.
Факт: одна строка — `payment | transaction_id | character varying`.
Вердикт: OK — `transaction_id` не первичный и не внешний ключ, а внешний идентификатор транзакции платежного провайдера (BR-8.2, BR-8.3), его формат задает провайдер, поэтому `varchar(20)`. Все PK и FK (`*_id`) — `uuid`.

### B.5. Enum-типы

```sql
SELECT t.typname, array_agg(e.enumlabel ORDER BY e.enumsortorder) AS values
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON n.oid = t.typnamespace
WHERE n.nspname = 'vizgaleva_food'
GROUP BY t.typname
ORDER BY t.typname;
```

Ожидается: 8 типов со значениями из constraints.md.
Факт:
```
 courier_status     | {свободен,занят,на_доставке,уволен}
 order_pay_status   | {ожидает,оплачен,ошибка}
 order_status       | {создан,готовится,в_доставке,доставлен,отменён}
 payment_status     | {успех,ошибка,в_обработке}
 payment_type       | {карта,наличные,безнал}
 product_status     | {доступно,нет_в_наличии,архив}
 restaurant_status  | {активен,неактивен}
 review_entity_type | {блюдо,ресторан,заказ}
```
Вердикт: OK

### B.6. FK-ограничения

```sql
SELECT conname, conrelid::regclass AS tbl, confrelid::regclass AS ref
FROM pg_constraint
WHERE contype = 'f'
  AND connamespace = 'vizgaleva_food'::regnamespace
ORDER BY tbl, conname;
```

Ожидается: не менее 15 FK, все из erd.md.
Факт: 20 FK — все 15 связей ERD + 5 составных FK из constraints.md:
```
 client_address_address_id_fkey   | client_address  | address
 client_address_client_id_fkey    | client_address  | client
 courier_pay_courier_id_fkey      | courier_pay     | courier
 order_address_belongs_to_client  | "order"         | client_address    -- составной, BR-7.4
 order_address_id_fkey            | "order"         | address
 order_client_id_fkey             | "order"         | client
 order_courier_id_fkey            | "order"         | courier
 order_restaurant_id_fkey         | "order"         | restaurant
 order_structure_order_id_fkey    | order_structure | "order"
 order_structure_product_id_fkey  | order_structure | product
 payment_amount_matches_order     | payment         | "order"           -- составной, BR-8.4
 payment_order_id_fkey            | payment         | "order"
 product_product_category_id_fkey | product         | product_category
 product_restaurant_id_fkey       | product         | restaurant
 restaurant_address_id_fkey       | restaurant      | address
 review_client_id_fkey            | review          | client
 review_client_of_order           | review          | "order"           -- составной, BR-9.2
 review_order_id_fkey             | review          | "order"
 review_product_in_order          | review          | order_structure   -- составной, BR-9.2
 review_restaurant_of_order       | review          | "order"           -- составной, BR-9.2
```
Вердикт: OK

### B.7. Пароль — MD5

Выполнено после C.2 (до генерации таблица пустая).

```sql
SELECT length(password) AS len, password
FROM client LIMIT 5;
```

Ожидается: `len = 32`, hex-строка.
Факт:
```
  32 | b8de2f0a3d1e6c1342c1dab47f6db484
  32 | 85f48eb80fe460039b26c979cfb39cda
  32 | c11277bf947985b1634e878a3686a4d6
  32 | 3033fd52a9f3388ecbcf5331bc6270a9
  32 | 181ec4fb5cc4ac5bf6c68da450831bfe
```
Вердикт: OK

---

## C. FOOD-102: `insert_test_data(value)`

### C.1. Чистая схема

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: `CALL`
Вердикт: OK

### C.2. Первый запуск

```sql
CALL insert_test_data(10);
```

Ожидается: без ошибок.
Факт: `CALL`
Вердикт: OK

### C.3. Распределение строк (BR-11.7)

```sql
SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
ORDER BY tbl;
```

Ожидается: 10, 10, 10, 10, 50, 50, 50, 50, 50.
Факт:
```
 address          |    50
 client           |    10
 courier          |    10
 order            |    50
 payment          |    92
 product          |    50
 product_category |    10
 restaurant       |    10
 review           |    50
```
Вердикт: OK — все таблицы по BR-11.7, кроме `payment`: 92 вместо 50. Это решение по подсказке из файла all_examples.sql (раздел 8c): на каждый заказ генерируется 1–3 попытки оплаты, ровно одна успешная (BR-8.1), неуспешные — только картой/безналом. Поэтому попыток больше, чем заказов.

### C.4. Адреса ресторанов vs клиентов (BR-11.7)

```sql
SELECT 'restaurant addresses' AS cat, count(*) FROM restaurant WHERE address_id IS NOT NULL
UNION ALL
SELECT 'total addresses', count(*) FROM address;
```

Ожидается: 10 ресторанных адресов, 50 всего → 40 клиентских.
Факт: `restaurant addresses | 10`, `total addresses | 50` → 40 клиентских.
Вердикт: OK

### C.5. Нет пустых строк (BR-11.3)

Проверены все строковые поля всех таблиц:

```sql
SELECT
 (SELECT count(*) FROM client WHERE login = '' OR password = '' OR trim(phone_number) = '')
+(SELECT count(*) FROM address WHERE street = '' OR house_number = '' OR apartment_office = '')
+(SELECT count(*) FROM restaurant WHERE restaurant_name = '' OR description = '' OR company_details = '')
+(SELECT count(*) FROM courier WHERE fio = '' OR trim(phone_number) = '')
+(SELECT count(*) FROM product_category WHERE product_category_name = '')
+(SELECT count(*) FROM product WHERE product_name = '' OR description = '' OR photo_url = '')
+(SELECT count(*) FROM "order" WHERE description = '')
+(SELECT count(*) FROM payment WHERE transaction_id = '')
+(SELECT count(*) FROM review WHERE description = '' OR photo_url = '') AS empty_strings;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### C.6. Нет NULL там, где запрещено (BR-11.3)

Проверены все NOT NULL поля (и `transaction_id` у безналичных оплат):

```sql
SELECT
 (SELECT count(*) FROM "order" WHERE client_id IS NULL OR restaurant_id IS NULL OR courier_id IS NULL OR address_id IS NULL
   OR total_amount IS NULL OR commission IS NULL OR order_amount IS NULL OR order_timestamp IS NULL
   OR status IS NULL OR pay_status IS NULL OR description IS NULL)
+(SELECT count(*) FROM payment WHERE payment_type IS NULL OR amount IS NULL OR transaction_timestamp IS NULL OR status IS NULL
   OR (payment_type <> 'наличные' AND transaction_id IS NULL))
+(SELECT count(*) FROM review WHERE client_id IS NULL OR order_id IS NULL OR entity_id IS NULL OR entity_type IS NULL
   OR rating IS NULL OR description IS NULL OR review_timestamp IS NULL)
+(SELECT count(*) FROM courier WHERE fio IS NULL OR phone_number IS NULL OR status IS NULL OR hire_date IS NULL OR coefficient IS NULL)
+(SELECT count(*) FROM product WHERE product_name IS NULL OR price IS NULL OR status IS NULL OR description IS NULL)
+(SELECT count(*) FROM restaurant WHERE restaurant_name IS NULL OR description IS NULL OR company_details IS NULL OR status IS NULL)
+(SELECT count(*) FROM courier_pay WHERE amount IS NULL OR coefficient_used IS NULL) AS forbidden_nulls;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### C.7. Минимум один активный курьер (BR-6.6)

```sql
SELECT count(*) FROM courier WHERE status != 'уволен';
```

Ожидается: `>= 1`.
Факт: `8`
Вердикт: OK

### C.8. `courier_pay` консистентен с правилами (BR-10.2)

Проверены все строки (`amount` против ожидаемой суммы), месяц — по `delivery_timestamp`:

```sql
SELECT count(*) AS rows_total,
       count(*) FILTER (WHERE cp.amount = round(coalesce((
           SELECT sum(o.commission) FROM "order" o
           WHERE o.courier_id = cp.courier_id AND o.status = 'доставлен'
             AND extract(year  from o.delivery_timestamp) = cp.year
             AND extract(month from o.delivery_timestamp) = cp.month), 0) * cp.coefficient_used, 2)) AS amount_eq_expected
FROM courier_pay cp;
```

Ожидается: `amount = expected_amount` в каждой строке.
Факт: `rows_total = 60`, `amount_eq_expected = 60`. Примеры строк с ненулевой суммой:
```
 year | month | amount | coefficient_used | expected_amount
 2026 |     5 |  90.65 |             0.10 |           90.65
 2026 |     6 | 106.39 |             0.10 |          106.39
 2026 |     6 |  58.75 |             0.10 |           58.75
 2026 |     7 |  79.28 |             0.10 |           79.28
 2026 |     8 |  26.71 |             0.10 |           26.71
```
Вердикт: OK

### C.9. Повторный вызов не ломает

```sql
DO $$
BEGIN
    FOR i IN 1..10 LOOP
        CALL insert_test_data(10);
    END LOOP;
END $$;
```

Ожидается: без ошибок, данные добавляются или заменяются.
Факт: `DO` без ошибок. Данные добавляются: `client = 110`, `order = 550`, `product_category = 110`. Уникальные поля (логин, телефон, адрес, название категории, id транзакции) генерируются так, чтобы не совпасть с уже существующими.
Вердикт: OK

---

## D. Проверки бизнес-правил на сгенерированных данных

Проверки выполнены на данных после C.9 (11 вызовов `insert_test_data(10)`).

### D.1. Все FK валидны (нет orphans)

Запрос из шаблона (7 проверок `LEFT JOIN ... IS NULL`).

Ожидается: все 0.
Факт:
```
 order_structure → order   |       0
 order_structure → product |       0
 payment → order           |       0
 review → order            |       0
 courier_pay → courier     |       0
 client_address → client   |       0
 client_address → address  |       0
```
Вердикт: OK

### D.2. Минимальная сумма заказа (BR-1.8)

```sql
SELECT count(*) FROM "order" WHERE total_amount < 1000;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.3. Комиссия = 10% (BR-1.4)

```sql
SELECT count(*) FROM "order" WHERE round(order_amount * 0.10, 2) != commission;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.4. `total_amount = order_amount + commission`

```sql
SELECT count(*) FROM "order"
WHERE round(order_amount + commission, 2) != total_amount;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.5. Дата доставки не раньше создания (BR-7.13)

```sql
SELECT count(*) FROM "order"
WHERE delivery_timestamp IS NOT NULL AND delivery_timestamp < order_timestamp;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.6. Адрес доставки принадлежит клиенту (BR-7.4)

```sql
SELECT count(*) FROM "order" o
LEFT JOIN client_address ca
  ON ca.client_id = o.client_id AND ca.address_id = o.address_id
WHERE ca.client_id IS NULL;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.7. Все блюда в заказе из одного ресторана (BR-7.3)

```sql
SELECT count(DISTINCT os.order_id)
FROM order_structure os
JOIN "order" o ON os.order_id = o.order_id
JOIN product p ON os.product_id = p.product_id
WHERE p.restaurant_id != o.restaurant_id;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.8. Ровно одна успешная оплата на заказ (BR-8.1)

```sql
SELECT order_id, count(*) AS cnt
FROM payment
WHERE status = 'успех'
GROUP BY order_id
HAVING count(*) != 1;

-- дополнительно: заказы совсем без успешной оплаты
SELECT count(*) AS orders_without_success FROM "order" o
WHERE NOT EXISTS (SELECT 1 FROM payment p WHERE p.order_id = o.order_id AND p.status = 'успех');
```

Ожидается: пусто.
Факт: первый запрос — пусто; заказов без успешной оплаты — `0`.
Вердикт: OK

### D.9. Сумма оплаты = `total_amount` заказа (BR-8.4)

```sql
SELECT count(*) FROM payment p
JOIN "order" o ON p.order_id = o.order_id
WHERE p.amount != o.total_amount;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.10. Нет дубликатов в `client_address` (BR-2.5)

```sql
SELECT client_id, address_id, count(*)
FROM client_address
GROUP BY client_id, address_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто
Вердикт: OK

### D.11. Нет дубликатов в `order_structure` (BR-7.16)

```sql
SELECT order_id, product_id, count(*)
FROM order_structure
GROUP BY order_id, product_id
HAVING count(*) > 1;
```

Ожидается: пусто.
Факт: пусто
Вердикт: OK

### D.12. `work_end > work_start` (BR-4.4)

```sql
SELECT count(*) FROM restaurant WHERE work_end <= work_start;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.13. `dismissal_date >= hire_date` (BR-6.3)

```sql
SELECT count(*) FROM courier
WHERE dismissal_date IS NOT NULL AND dismissal_date < hire_date;
```

Ожидается: 0.
Факт: `0`
Вердикт: OK

### D.14. Рейтинг блюд/ресторанов соответствует отзывам (BR-9.6)

Проверены все блюда с рейтингом; округление до 1 знака (`rating numeric(2,1)`):

```sql
SELECT count(*) AS rated,
       count(*) FILTER (WHERE p.rating = (SELECT round(avg(r.rating), 1) FROM review r
                         WHERE r.entity_type = 'блюдо' AND r.entity_id = p.product_id)) AS eq_expected
FROM product p
WHERE p.rating IS NOT NULL;
```

Ожидается: `rating = expected`.
Факт: `rated = 156`, `eq_expected = 156`. Примеры: `5.0 = 5.0`, `2.0 = 2.0`, `4.0 = 4.0`.
Вердикт: OK

---

## E. Функции и процедуры

### E.1. `add_product` — успешный вызов

```sql
SELECT count(*) AS before FROM product;

SELECT (SELECT restaurant_id FROM restaurant LIMIT 1) AS r,
       (SELECT product_category_id FROM product_category LIMIT 1) AS c \gset

CALL add_product(
    p_restaurant_id       => :'r',
    p_product_category_id => :'c',
    p_product_name        => 'Тестовое блюдо',
    p_price               => 250,
    p_status              => 'доступно',
    p_description         => 'Описание',
    p_photo_url           => 'https://cdn.foodexpress.ru/img/test.jpg'
);

SELECT count(*) AS after FROM product;
```

Ожидается: `after = before + 1`.
Факт: `before = 550`, `NOTICE: Блюдо "Тестовое блюдо" добавлено, product_id = 8b3a1ef3-6d2e-4061-b28a-79a27141d99e`, `after = 551`.
Вердикт: OK

### E.2. `add_product` — падает на несуществующий ресторан

```sql
CALL add_product(
    p_restaurant_id       => '00000000-0000-0000-0000-000000000000',
    p_product_category_id => :'c',
    p_product_name        => 'Тестовое блюдо',
    p_price               => 250,
    p_status              => 'доступно',
    p_description         => 'Описание'
);
```

Ожидается: ошибка с внятным сообщением.
Факт: `ERROR: Ресторан с restaurant_id = 00000000-0000-0000-0000-000000000000 не существует` (SQLSTATE 23503 foreign_key_violation).
Вердикт: OK

### E.3. `rating_change` — пересчитывает рейтинг

Чтобы отзыв прошел ограничения BR-9.2 (клиент этого заказа, блюдо из этого заказа, один отзыв на объект в заказе), берется позиция заказа, на которую еще нет отзыва, а у блюда уже есть другой отзыв:

```sql
SELECT os.order_id AS e3_order, os.product_id AS e3_product, o.client_id AS e3_client
  FROM order_structure os JOIN "order" o USING (order_id)
 WHERE NOT EXISTS (SELECT 1 FROM review r WHERE r.order_id = os.order_id AND r.entity_type = 'блюдо' AND r.entity_id = os.product_id)
   AND EXISTS (SELECT 1 FROM review r WHERE r.entity_type = 'блюдо' AND r.entity_id = os.product_id)
 LIMIT 1 \gset

SELECT rating FROM product WHERE product_id = :'e3_product';

INSERT INTO review (review_id, client_id, review_timestamp, entity_id, entity_type, order_id, description, rating)
VALUES (exts.uuid_generate_v4(), :'e3_client', localtimestamp, :'e3_product', 'блюдо', :'e3_order', 'Тестовый отзыв', 5)
RETURNING review_id AS e3_review \gset

SELECT rating FROM product WHERE product_id = :'e3_product';
```

Ожидается: `rating` пересчитан.
Факт: до вставки `rating = 4.0` (1 отзыв с оценкой 4); после вставки отзыва с оценкой 5 — `rating = 4.5` (ожидаемое среднее 4.5).
Вердикт: OK

### E.4. `rating_change` — удаление отзыва

```sql
DELETE FROM review WHERE review_id = :'e3_review';
SELECT rating FROM product WHERE product_id = :'e3_product';
```

Ожидается: если других отзывов нет — `rating IS NULL`; иначе — пересчитан.
Факт: `DELETE 1`, `rating = 4.0` — остался один другой отзыв, рейтинг вернулся к его оценке.
Вердикт: OK

### E.5. `get_statistic()`

```sql
SELECT * FROM get_statistic();
```

Ожидается:
- Колонки: `restaurant_name`, `best_product_name`, `total_amount`, `avg_amount`, `best_user`.
- По одной строке на ресторан.
- `best_user` = `client.login` (не NULL при наличии заказов).

Факт: колонки ровно эти. 110 строк при 110 ресторанах. Строк с заказами и `best_user IS NULL` — 0. Первые строки:
```
 restaurant_name | best_product_name | total_amount | avg_amount |    best_user
 Bésame mucho    | Карбонара         |      3086.33 |    3086.33 | user_c755b4ef_8
 Bésame mucho    |                   |            0 |          0 |
 Bésame mucho    | Греческий         |      5115.15 |    5115.15 | user_75d1d23d_1
 Grazie pizza    | Поке              |      1356.70 |    1356.70 | user_e378b7a3_3
 IL Патио        |                   |            0 |          0 |
```
(Одинаковые названия — разные рестораны: название берется из списка и уникальным быть не обязано. У ресторана без доставленных заказов суммы 0, блюда и клиента нет.)
Вердикт: OK

### E.6. `courier_salary()`

```sql
-- До
CREATE TEMP TABLE coef_before AS SELECT courier_id, coefficient, dismissal_date FROM courier;

CALL courier_salary();

-- После
SELECT count(*) FILTER (WHERE b.dismissal_date IS NULL)                                   AS working,
       count(*) FILTER (WHERE b.dismissal_date IS NOT NULL)                               AS dismissed,
       count(*) FILTER (WHERE b.dismissal_date IS NULL AND c.coefficient = 0.1)           AS working_coef_eq_0_1,
       count(*) FILTER (WHERE b.dismissal_date IS NOT NULL AND b.coefficient <> c.coefficient) AS dismissed_coef_changed
  FROM coef_before b JOIN courier c USING (courier_id);
SELECT count(*) FROM courier_pay
 WHERE year = extract(year from current_date) AND month = extract(month from current_date);
SELECT count(*) FROM "order"
 WHERE status = 'доставлен' AND date_trunc('month', delivery_timestamp) = date_trunc('month', localtimestamp);
```

Ожидается:
- `courier.coefficient` пересчитан для работающих (по BR-10.2).
- У уволенных — не изменился.
- `courier_pay` содержит запись за текущий месяц.

Факт: `NOTICE: Зарплата за 11.2026: записей в courier_pay 0, обновлено коэффициентов 89`.
- работающих 89 — у всех коэффициент пересчитан;
- уволенных 21 — коэффициент не изменился ни у одного (BR-10.6);
- записей в `courier_pay` за текущий месяц — 0, доставленных заказов в текущем месяце — 0.
Почему записи за текущий месяц нет: тестовые данные генерируются за последние 180 дней без текущего месяца (за текущий месяц зарплата еще не начислена — процедура запускается в последний день месяца, BR-10.2). А `courier_salary` вносит запись в `courier_pay` только по курьерам, у которых в этом месяце есть доставленные заказы.



### E.7. `courier_salary()` — повторный вызов

```sql
CALL courier_salary();
SELECT count(*) FROM courier_pay
WHERE year = extract(year from current_date)
  AND month = extract(month from current_date);
```

Ожидается: количество не изменилось.
Факт: до — `0`, после — `0`. На данных с доставками (доп. проверка к E.6): после первого вызова 62 строки, после повторного — 62; сумма и `coefficient_used` те же (коэффициент текущего месяца при повторном вызове берется из уже созданной записи, а не из обновленного `courier.coefficient`).
Вердикт: OK

---

## F. Представление `how_much_money`

### F.1. Колонки

```sql
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_schema = 'vizgaleva_food'
  AND table_name = 'how_much_money'
ORDER BY ordinal_position;
```

Ожидается: `year_month` (text), остальные numeric.
Факт:
```
 year_month          | text
 sum_no_commission   | numeric
 sum_with_commission | numeric
 commission          | numeric
 prev_commission     | numeric
 commission_diff     | numeric
 courier_pay         | numeric
 net_profit          | numeric
```
Вердикт: OK

### F.2. Месяцы покрыты

```sql
SELECT * FROM how_much_money ORDER BY year_month;
```

Ожидается: месяцы от первого доставленного заказа до последнего (не пропущено ни одного).
Факт: первый доставленный заказ — 2026-05, последний — 2026-10; в отчете 6 месяцев подряд:
```
 year_month | sum_no_commission | sum_with_commission | commission | prev_commission | commission_diff | courier_pay | net_profit
 2026-05    |          37510.81 |            41261.88 |    3751.07 |                 |                 |      375.10 |    3375.97
 2026-06    |         115744.01 |           127318.42 |   11574.41 |         3751.07 |         7823.34 |     1157.46 |   10416.95
 2026-07    |         146608.96 |           161269.88 |   14660.92 |        11574.41 |         3086.51 |     1466.11 |   13194.81
 2026-08    |         141700.61 |           155870.71 |   14170.10 |        14660.92 |         -490.82 |     1417.02 |   12753.08
 2026-09    |         117052.87 |           128758.16 |   11705.29 |        14170.10 |        -2464.81 |     1170.54 |   10534.75
 2026-10    |         161266.21 |           177392.84 |   16126.63 |        11705.29 |         4421.34 |     1612.66 |   14513.97
```
Вердикт: OK

### F.3. Месяцы без заказов присутствуют (BR-11.9)

```sql
SELECT year_month FROM how_much_money
WHERE sum_no_commission = 0 OR sum_no_commission IS NULL;
```

Ожидается: если в какие-то месяцы заказов не было — они есть в результате.
Факт: пусто — в сгенерированных данных доставки есть в каждом месяце. Отдельно проверяла при приемке FOOD-108: все доставки и выплаты за 2026-08 были убраны и строка `2026-08` осталась в отчете с нулевыми суммами, `net_profit = 0`, у 2026-09 `prev_commission = 0`.
Вердикт: OK

### F.4. Корректность сумм

```sql
SELECT count(*) AS rows,
       count(*) FILTER (WHERE commission = sum_with_commission - sum_no_commission)            AS commission_ok,
       count(*) FILTER (WHERE commission_diff IS NOT DISTINCT FROM commission - prev_commission) AS diff_ok,
       count(*) FILTER (WHERE net_profit = commission - courier_pay)                           AS net_ok,
       count(*) FILTER (WHERE prev_commission IS NULL)                                          AS first_month_null
FROM how_much_money;
```

Ожидается:
- `commission = sum_with_commission - sum_no_commission`.
- `commission_diff = commission - prev_commission` (NULL для первого месяца).
- `net_profit = commission - courier_pay`.

Факт: `rows = 6`, `commission_ok = 6`, `diff_ok = 6`, `net_ok = 6`, `first_month_null = 1` (2026-05).
Вердикт: OK

---

## G. Права `inspector`

### G.1. Права на схему

Под администратором:

```sql
SELECT nspname AS schema_name,
       has_schema_privilege('inspector', nspname, 'USAGE')  AS usage,
       has_schema_privilege('inspector', nspname, 'CREATE') AS create
FROM pg_namespace
WHERE nspname = 'vizgaleva_food';
```

Ожидается: `vizgaleva_food`, `true`, `true`.
Факт: `vizgaleva_food | t | t`
Вердикт: OK

### G.2. Права на таблицы

```sql
SELECT table_name, string_agg(privilege_type, ', ') AS privs
FROM information_schema.role_table_grants
WHERE grantee = 'inspector' AND table_schema = 'vizgaleva_food'
GROUP BY table_name;
```

Ожидается: у каждой таблицы `SELECT, INSERT, UPDATE, DELETE` (или `ALL`).
Факт: у всех 12 таблиц и представления `how_much_money` — `DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE` (= ALL PRIVILEGES).
Вердикт: OK

### G.3. `information_schema` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM information_schema.tables
WHERE table_schema = 'vizgaleva_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: `13` — 12 таблиц + представление `how_much_money` (`information_schema.tables` включает представления).
Вердикт: OK

### G.4. `pg_catalog` читается под `inspector`

```sql
SET ROLE inspector;
SELECT count(*) FROM pg_catalog.pg_tables
WHERE schemaname = 'vizgaleva_food';
RESET ROLE;
```

Ожидается: 12 + N.
Факт: `12`
Вердикт: OK

### G.5. Все процедуры/функции работают под `inspector`

```sql
SET ROLE inspector;
SET search_path TO vizgaleva_food, exts;

CALL erase_test_data();
CALL insert_test_data(10);
CALL courier_salary();
SELECT * FROM get_statistic();
SELECT * FROM how_much_money LIMIT 5;

RESET ROLE;
```

Ожидается: без `permission denied`.
Факт: все вызовы выполнены: `CALL`, `CALL`, `CALL` (`NOTICE: Зарплата за 11.2026: записей в courier_pay 0, обновлено коэффициентов 9`), `get_statistic` — 10 строк, `how_much_money` — 4 строки. `permission denied` — 0 за весь прогон. Дополнительно проверено подключение `inspector` по сети с паролем `NetoSQL2025` (`psql -h <адрес> -U inspector`): неверный пароль отклоняется, с верным все вызовы проходят.
Вердикт: OK

---

## H. Оптимизация `get_statistic` (BR-11.8)

Под `inspector`, на данных после G.5 (10 курьеров, 50 заказов).

### H.1. `EXPLAIN ANALYZE` — паттерн «избыточные подзапросы»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       (SELECT count(*) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS cnt,
       (SELECT coalesce(sum(commission), 0) FROM "order" o WHERE o.courier_id = c.courier_id AND o.status = 'доставлен') AS commission_sum
FROM courier c;
```

Ожидается: два SubPlan, каждый — скан `"order"`.
Факт: время 0.253 мс, план:
```
 Seq Scan on courier c (actual rows=10 loops=1)
   SubPlan 1
     ->  Aggregate (loops=10)
           ->  Seq Scan on "order" o (loops=10)
   SubPlan 2
     ->  Aggregate (loops=10)
           ->  Seq Scan on "order" o_1 (loops=10)
```
Два SubPlan, `"order"` сканируется 2 × 10 = 20 раз.

### H.2. `EXPLAIN ANALYZE` — паттерн «один JOIN»

```sql
EXPLAIN ANALYZE
SELECT c.courier_id,
       count(o.order_id) AS cnt,
       coalesce(sum(o.commission), 0) AS commission_sum
FROM courier c
LEFT JOIN "order" o ON o.courier_id = c.courier_id AND o.status = 'доставлен'
GROUP BY c.courier_id;
```

Ожидается: один `Hash Left Join`, один скан `"order"`. Время меньше, чем в H.1.
Факт: время 0.046 мс (в 5.5 раза меньше H.1), план:
```
 HashAggregate
   ->  Hash Left Join
         ->  Seq Scan on courier c (loops=1)
         ->  Hash
               ->  Seq Scan on "order" o (loops=1)
```

### H.3. Применить к `get_statistic`

```sql
EXPLAIN ANALYZE SELECT * FROM get_statistic();
```

Ожидается: без `LATERAL`, без множественных подзапросов к одной таблице, без оконных функций там, где хватает агрегата.
Факт: `EXPLAIN ANALYZE` над функцией показывает только `Function Scan on get_statistic` (0.587 мс), поэтому внутренний план снят через `auto_explain` (под администратором, `auto_explain.log_nested_statements = on`). Ключевые узлы:
```
 CTE delivered
   ->  Seq Scan on "order" o                    -- order читается 1 раз (CTE MATERIALIZED)
 CTE rest_client
   ->  HashAggregate                            -- группировка (ресторан, клиент)
         ->  CTE Scan on delivered
 CTE best_client
   ->  Unique -> Sort (restaurant_id, cnt DESC, random())   -- DISTINCT ON, без окон
 CTE best_product
   ->  Unique -> Incremental Sort -> GroupAggregate
         ->  Hash Join
               ->  Seq Scan on order_structure s           -- order_structure читается 1 раз
               ->  Hash -> CTE Scan on delivered
 ->  Hash Left Join ... Seq Scan on restaurant / product / client   -- каждая по 1 разу
```
Каждая таблица (`order`, `order_structure`, `restaurant`, `product`, `client`) читается один раз; `LATERAL`, `SubPlan` и `WindowAgg` нет; «лучший» выбирается через `DISTINCT ON` по уже сгруппированным строкам. Время выполнения запроса 0.36 мс.
Вердикт: OK

---

## I. Очистка и повторная генерация

### I.1. `erase_test_data` очищает всё

```sql
CALL erase_test_data();

SELECT 'client' AS tbl, count(*) FROM client
UNION ALL SELECT 'courier', count(*) FROM courier
UNION ALL SELECT 'product_category', count(*) FROM product_category
UNION ALL SELECT 'restaurant', count(*) FROM restaurant
UNION ALL SELECT 'address', count(*) FROM address
UNION ALL SELECT 'product', count(*) FROM product
UNION ALL SELECT 'order', count(*) FROM "order"
UNION ALL SELECT 'review', count(*) FROM review
UNION ALL SELECT 'payment', count(*) FROM payment
UNION ALL SELECT 'order_structure', count(*) FROM order_structure
UNION ALL SELECT 'client_address', count(*) FROM client_address
UNION ALL SELECT 'courier_pay', count(*) FROM courier_pay;
```

Ожидается: все 0.
Факт: все 12 таблиц — `0`.
Вердикт: OK

### I.2. Повторный `erase_test_data` не падает

```sql
CALL erase_test_data();
```

Ожидается: без ошибок.
Факт: `CALL`
Вердикт: OK

### I.3. После очистки `insert_test_data` снова работает

```sql
CALL insert_test_data(10);
SELECT count(*) FROM "order";
```

Ожидается: 50.
Факт: `50`
Вердикт: OK
