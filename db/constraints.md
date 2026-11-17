# Обоснование ограничений


Таблица `order` оставлена с этим именем в двойных кавычках (`"order"`), а не переименована, — BR-13.1 разрешает оба варианта

---

## Enum-типы


| Тип | Значения | BR |
|---|---|---|
| `restaurant_status` | `'активен'`, `'неактивен'` | BR-4.3 |
| `product_status` | `'доступно'`, `'нет_в_наличии'`, `'архив'` | BR-5.5 |
| `courier_status` | `'свободен'`, `'занят'`, `'на_доставке'`, `'уволен'` | BR-6.2 |
| `order_status` | `'создан'`, `'готовится'`, `'в_доставке'`, `'доставлен'`, `'отменён'` | BR-7.7 |
| `order_pay_status` | `'ожидает'`, `'оплачен'`, `'ошибка'` | BR-7.9 |
| `payment_type` | `'карта'`, `'наличные'`, `'безнал'` | BR-8.2 |
| `payment_status` | `'успех'`, `'ошибка'`, `'в_обработке'` | BR-8.2 |
| `review_entity_type` | `'блюдо'`, `'ресторан'`, `'заказ'` | BR-9.1 |

---

## Ловушки

### Ловушка 1: `payment` — неполная сущность

**Какие атрибуты добавил в `payment` и почему** (BR-8.2):

```
В исходной схеме у PAYMENT только payment_id и order_id. По BR-8.2 у каждой попытки оплаты есть
тип, сумма, идентификатор транзакции, дата/время и статус, поэтому добавила 5 колонок:

payment_type           payment_type  NOT NULL  - тип оплаты (BR-8.2, BR-8.6)
amount                 numeric(12,2) NOT NULL  - сумма попытки, = order.total_amount (BR-8.4)
transaction_id         varchar(20)   UNIQUE    - id транзакции от платежного провайдера (BR-8.2, BR-8.3);
                                                 у оплаты наличными NULL - транзакции у провайдера нет
transaction_timestamp  timestamp     NOT NULL  - дата и время попытки (BR-8.2), у наличных - время получения денег курьером
status                 payment_status NOT NULL - статус попытки (BR-8.2)

```

**Где хранится тип оплаты — `payment` или `order`** (BR-8.6):

```
Тип оплаты храню в payment - BR-8.6.
В order храню только агрегированный статус оплаты pay_status -BR-7.8-, его пересчитывает
триггер payment_update_order_pay_status по попыткам (BR-8.7).
```

### Ловушка 2: `order.address_id` — принадлежность клиенту (BR-7.4)

**Как обеспечено, что адрес доставки принадлежит клиенту:**

```
Через составной FK на таблицу client_address:

CONSTRAINT order_address_belongs_to_client
    FOREIGN KEY (client_id, address_id)
    REFERENCES vizgaleva_food.client_address (client_id, address_id)
    ON DELETE RESTRICT

Пара (client_id, address_id) из заказа обязана быть в client_address, поэтому оформить доставку
на адрес, который не привязан к этому клиенту, нельзя -BR-7.4.
ON DELETE RESTRICT - клиент не может отвязать адрес, на который уже были заказы,
иначе пропадет история заказов (BR-3.5).
```

### Ловушка 3: `order_structure` — один ресторан в заказе (BR-7.3)

**Как обеспечено, что все блюда из `order.restaurant_id`:**

```
Триггер order_structure_check_restaurant (BEFORE INSERT OR UPDATE на order_structure).
Перед вставкой/изменением позиции он проверяет, что product.restaurant_id блюда совпадает
с order.restaurant_id заказа, иначе RAISE EXCEPTION.
Решила сделать триггер, а не FK-  т.к. ресторан блюда хранится в product, а не в order_structure, поэтому
составной FK можно было бы сделать только добавив в order_structure лишнюю колонку restaurant_id,
которой нет в начальной схеме
```

### Ловушка 4: `review` — полиморфизм (BR-9.1)

**Как реализована валидность `review.entity_id`:**

```
Сделала через гибрид: полиморфизм как в схема (entity_type + entity_id, на них опирается BR-9.6) и
служебные вычисляемые колонки для составных FK.

product_id    uuid GENERATED ALWAYS AS (CASE WHEN entity_type = 'блюдо'    THEN entity_id END) STORED
restaurant_id uuid GENERATED ALWAYS AS (CASE WHEN entity_type = 'ресторан' THEN entity_id END) STORED

Обычный FK на отзыв поставить нельзя - он ссылается то на product, то на restaurant, то на order.
Вычисляемые колонки раскладывают entity_id по типам: заполнена только колонка нужного типа, остальные NULL.
На них составные FK, которые проверяют BR-9.2:

review_product_in_order    FK (order_id, product_id)    -> order_structure(order_id, product_id)  - блюдо есть в этом заказе
review_restaurant_of_order FK (order_id, restaurant_id) -> order(order_id, restaurant_id)         - ресторан этого заказа
review_order_entity_check  CHECK (entity_type <> 'заказ' OR entity_id = order_id)                  - отзыв на этот же заказ
review_client_of_order     FK (order_id, client_id)     -> order(order_id, client_id)             - пишет клиент этого заказа

```

---

## CHECK-ограничения

| Таблица | Столбец | Условие | BR | Обоснование |
|---|---|---|---|---|
| `restaurant` | `rating` | `rating BETWEEN 0 AND 5` | BR-4.2 | BR-4.2 задает диапазон рейтинга ресторана |
| `restaurant` | `work_start`, `work_end` | `work_end > work_start` | BR-4.4 | BR-4.4 требует, чтобы время закрытия было позже открытия (работа через полночь невозможна) |
| `product` | `price` | `price >= 0` | BR-5.3 | В BR-5.3  неотрицательная цена |
| `product` | `rating` | `rating BETWEEN 0 AND 5` | BR-5.4 | В BR-5.4 задается  рейтинг блюда |
| `product` | `photo_url` | `photo_url ~ '^https?://'` | BR-5.6 | В BR-5.6  фото — это ссылка (URL), сделала проверку на валидность адреса|
| `courier` | `status`, `dismissal_date` | `(status = 'уволен') = (dismissal_date IS NOT NULL)` | BR-6.3, BR-11.3 | У BR-6.3 есть дата увольнения,у BR-11.3 — ее отсутствие у работающего |
| `courier` | `hire_date`, `dismissal_date` | `dismissal_date >= hire_date` | BR-6.1, BR-6.3 | даты найма и увольнения из BR-6.1/BR-6.3 должны быть согласованы: уволить раньше найма нельзя  |
| `courier` | `coefficient` | `coefficient BETWEEN 0.1 AND 0.5` | BR-6.4 | BR-6.4 задает диапазон коэффициента, границы включительно |
| `courier_pay` | `month` | `month BETWEEN 1 AND 12` | BR-10.3 | без проверки month = 13 обходил бы ключ «одна запись за месяц» из BR-10.3 |
| `order` | `total_amount` | `total_amount >= 1000` | BR-1.8, BR-7.11 | В BR-7.11 задана минимальная общач сумму заказа.  |
| `order` | `status`, `delivery_timestamp` | `(status = 'доставлен') = (delivery_timestamp IS NOT NULL)` | BR-7.12, BR-11.3 | BR-7.12 — время доставки заполняется при статусе «доставлен», BR-11.3 — у недоставленного его нет |
| `order` | `order_timestamp`, `delivery_timestamp` | `delivery_timestamp >= order_timestamp` | BR-7.13 | BR-7.13  -запрещается делать доставку раньше создания заказа |
| `order_structure` | `quantity` | `quantity > 0` | BR-7.15 | BR-7.15 требует положительное количество |
| `payment` | `payment_type`, `transaction_id` | `(payment_type = 'наличные') = (transaction_id IS NULL)` | BR-8.2, BR-8.3 | BR-8.3 — id транзакции приходит от платежного провайдера, а при оплате наличными курьеру транзакции у провайдера нет. Поэтому id обязателен у карты/безнала и отсутствует у наличных |
| `payment` | `payment_type`, `status` | `payment_type <> 'наличные' OR status = 'успех'` | BR-8.2 | статусы из BR-8.2 для наличных: деньги получены курьером при доставке, ошибки и обработки у наличных не бывает. Сделала осознанно, пусть будет требование бизнеса |
| `review` | `rating` | `rating BETWEEN 1 AND 5` | BR-9.4 | BR-9.4 задает диапазон рейтинга отзыва |
| `review` | `entity_type`, `entity_id` | `entity_type <> 'заказ' OR entity_id = order_id` | BR-9.2 | BR-9.2 — отзыв на заказ может быть только на тот заказ, к которому он привязан |

---

## UNIQUE-ограничения

| Таблица | Столбцы | BR | Обоснование |
|---|---|---|---|
| `client` | `login` | BR-2.2 | BR-2.2 требует уникальный логин |
| `client` | `phone_number` | BR-2.2 | BR-2.2 требует уникальный телефон |
| `client_address` | `(client_id, address_id)` — PRIMARY KEY | BR-2.5 | BR-2.5 запрещает привязать один адрес к одному клиенту дважды |
| `address` | `(street, house_number, apartment_office)` `NULLS NOT DISTINCT` (`address_restoran_key`) | BR-3.3 | BR-3.3 запрещает двум ресторанам делить один физический адрес: без этого можно завести две строки с одинаковым адресом и разными `address_id`. `NULLS NOT DISTINCT` — чтобы адреса без квартиры тоже считались одинаковыми (PostgreSQL 15+) |
| `restaurant` | `address_id` | BR-3.3, BR-3.4 | BR-3.3 запрещает двум ресторанам делить один адрес, BR-3.4 — адрес ресторана только у одного ресторана |
| `product_category` | `product_category_name` | BR-5.7 | BR-5.7 — категория это справочник, двух одинаковых записей в справочнике быть не должно |
| `courier_pay` | `(year, month, courier_id)` — PRIMARY KEY | BR-10.3 | BR-10.3 — за один месяц у одного курьера ровно одна запись |
| `order_structure` | `(order_id, product_id)` — PRIMARY KEY | BR-7.16 | BR-7.16 запрещает одно блюдо в заказе дважды |
| `payment` | `transaction_id` | BR-8.3 | BR-8.3 требует уникальный id транзакции. NULL у наличных не мешают: UNIQUE допускает несколько NULL |
| `payment` | `(order_id) WHERE status = 'успех'` — частичный уникальный индекс `payment_one_success_per_order` | BR-8.1 | BR-8.1 — у заказа ровно одна успешная попытка. Индекс не дает вторую успешную; попыток с ошибкой может быть сколько угодно. «Хотя бы одна» схемой не проверяется — по BR-8.7 у заказа бывает статус «ожидает»/«ошибка» без успешной попытки |
| `review` | `(order_id, entity_type, entity_id)` | BR-9.5 | BR-9.5 — в рамках заказа не больше одного отзыва на каждый объект (до N+2 отзывов) |
| `order` | `(order_id, total_amount)` | BR-8.4 | служебный: нужен для составного FK `payment_amount_matches_order`, FK может ссылаться только на UNIQUE/PK |
| `order` | `(order_id, client_id)` | BR-9.2 | служебный: нужен для составного FK `review_client_of_order` |
| `order` | `(order_id, restaurant_id)` | BR-9.2 | служебный: нужен для составного FK `review_restaurant_of_order` |

---

## FK-ограничения

| Таблица | Столбцы | → Таблица | BR | Обоснование |
|---|---|---|---|---|
| `client_address` | `client_id` (`ON DELETE CASCADE`) | `client(client_id)` | BR-2.4, BR-3.5 | BR-2.4 — у клиента несколько адресов (связь M:N). CASCADE — при удалении клиента удаляются только его привязки, сами адреса остаются (BR-3.5) |
| `client_address` | `address_id` (`ON DELETE RESTRICT`) | `address(address_id)` | BR-2.4, BR-3.5 | BR-2.4 — один адрес у разных клиентов. RESTRICT — BR-3.5 запрещает удалять адрес, пока он используется |
| `restaurant` | `address_id` (`ON DELETE RESTRICT`) | `address(address_id)` | BR-3.3, BR-3.5 | BR-3.3 — у ресторана ровно один адрес; BR-3.5 — адрес не удаляется при удалении ресторана |
| `product` | `restaurant_id` | `restaurant(restaurant_id)` | BR-5.1 | BR-5.1 — блюдо принадлежит ровно одному ресторану |
| `product` | `product_category_id` | `product_category(product_category_id)` | BR-5.1, BR-5.7 | BR-5.1 — блюдо принадлежит ровно одной категории из справочника, BR-5.7 |
| `courier_pay` | `courier_id` | `courier(courier_id)` | BR-10.2 | BR-10.2 — выплата начисляется конкретному курьеру |
| `order` | `client_id` | `client(client_id)` | BR-7.1, BR-7.2 | BR-7.2 — заказ привязан к одному клиенту |
| `order` | `restaurant_id` | `restaurant(restaurant_id)` | BR-7.2 | BR-7.2 — заказ привязан к одному ресторану |
| `order` | `courier_id` | `courier(courier_id)` | BR-7.5 | BR-7.5 — доставку выполняет курьер |
| `order` | `address_id` (`ON DELETE RESTRICT`) | `address(address_id)` | BR-7.4, BR-3.5 | BR-7.4 — заказ доставляется по одному адресу; BR-3.5 — история заказов сохраняется |
| `order` | `(client_id, address_id)` (`ON DELETE RESTRICT`) | `client_address(client_id, address_id)` | BR-7.4 | BR-7.4 — адрес доставки только из адресов клиента (ловушка 2) |
| `order_structure` | `order_id` | `order(order_id)` | BR-7.14 | BR-7.14 — позиция принадлежит заказу |
| `order_structure` | `product_id` | `product(product_id)` | BR-7.14 | BR-7.14 — позиция — это блюдо и количество |
| `payment` | `order_id` | `order(order_id)` | BR-8.1 | BR-8.1 — у заказа несколько попыток оплаты (1:N) |
| `payment` | `(order_id, amount)` (`ON UPDATE RESTRICT`, `ON DELETE RESTRICT`) | `order(order_id, total_amount)` | BR-8.4, BR-1.5 | BR-8.4 — сумма попытки равна общей сумме заказа. CHECK не видит другую таблицу, поэтому составной FK. ON UPDATE RESTRICT — нельзя поменять сумму заказа, по которому уже есть оплаты |
| `review` | `client_id` | `client(client_id)` | BR-9.2 | BR-9.2 — отзыв оставляет клиент |
| `review` | `order_id` | `order(order_id)` | BR-9.2 | BR-9.2 — отзыв всегда связан с конкретным заказом |
| `review` | `(order_id, client_id)` | `order(order_id, client_id)` | BR-9.2 | BR-9.2 — отзыв пишет клиент этого заказа |
| `review` | `(order_id, restaurant_id)` | `order(order_id, restaurant_id)` | BR-9.2 | BR-9.2 — отзыв на ресторан только на ресторан этого заказа (ловушка 4) |
| `review` | `(order_id, product_id)` | `order_structure(order_id, product_id)` | BR-9.2 | BR-9.2 — отзыв на блюдо только на блюдо из этого заказа (ловушка 4) |

---

## NOT NULL (только бизнес-обязательные)

Остальные NOT NULL — поля из BR, которые по BR-11.3 обязательны, если бизнес не разрешает их пустыми.

| Таблица | Столбец | BR | Обоснование |
|---|---|---|---|
| `order` | `courier_id` | BR-1.3, BR-7.5 | BR-1.3 — только доставка, BR-7.5 — доставку выполняет курьер. Заказ без курьера не допускается, курьер назначается сразу при оформлении |
| `order` | `description` | BR-11.3 | комментарий к заказу есть в ERD, а правила, что он может быть пустым, в BR нет — поэтому по BR-11.3 обязателен |
| `restaurant` | `description`, `company_details` | BR-4.1, BR-4.5 | BR-4.1 перечисляет описание и реквизиты как атрибуты ресторана, исключений нет |
| `review` | `description` | BR-9.3 | BR-9.3 — текст у отзыва есть всегда, необязательна только фотография |
| `payment` | `transaction_timestamp` | BR-8.2 | BR-8.2 — дата и время есть у каждой попытки, в том числе у наличных (время получения денег курьером), хотя `transaction_id` у наличных NULL |
| `courier_pay` | `amount`, `coefficient_used` | BR-10.2 | BR-10.2 (п. 4) — запись содержит сумму и примененный коэффициент |

---

## NULL (осознанно разрешено)

| Таблица | Столбец | BR | Почему NULL |
|---|---|---|---|
| `address` | `apartment_office` | BR-3.2, BR-11.3 | для частных домов |
| `product` | `photo_url` | BR-5.6, BR-11.3 | фотография блюда необязательна |
| `review` | `photo_url` | BR-9.3, BR-11.3 | фотография в отзыве необязательна |
| `courier` | `dismissal_date` | BR-6.3, BR-11.3 | у работающего курьера даты увольнения нет (CHECK `courier_dismissal_date_check`) |
| `order` | `delivery_timestamp` | BR-7.12, BR-11.3 | у недоставленного заказа время доставки отсутствует (CHECK `order_delivery_consistency`) |
| `product` | `rating` | BR-9.7 | если отзывов на блюдо нет — рейтинг NULL |
| `restaurant` | `rating` | BR-9.7 | если отзывов на ресторан нет — рейтинг NULL |
| `payment` | `transaction_id` | BR-8.2, BR-8.3 | при оплате наличными транзакции у платежного провайдера нет (CHECK `payment_transaction_id_check`) |
| `review` | `product_id`, `restaurant_id` | BR-9.2 | служебные вычисляемые колонки: NULL, когда отзыв не на этот тип объекта (ловушка 4) |

---

## DEFAULT и GENERATED

| Таблица | Столбец | Что | Обоснование |
|---|---|---|---|
| все таблицы с собственным ID | `client_id`, `address_id`, `restaurant_id`, `courier_id`, `product_category_id`, `product_id`, `order_id`, `payment_id`, `review_id` | `DEFAULT exts.uuid_generate_v4()` | BR-11.1 — все ID UUID и генерируются на сервере через `exts.uuid_generate_v4()`. Схема `exts` уже создана (BR-13.3), скрипт ее не пересоздает. У `client_address`, `order_structure`, `courier_pay` ключ составной из FK, DEFAULT не нужен |
| `courier` | `coefficient` | `DEFAULT 0.1` | BR-6.5 — изначальный коэффициент нового курьера 0.1 |
| `order` | `pay_status` | `DEFAULT 'ожидает'` | BR-8.7 — у нового заказа попыток оплаты еще нет, статус «ожидает». Дальше его пересчитывает триггер `payment_update_order_pay_status` |
| `order` | `commission` | `GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED` | BR-1.4, BR-7.10 — комиссия фиксированные 10% от стоимости блюд. Хранится в СУБД, вручную записать нельзя |
| `order` | `total_amount` | `GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED` | BR-7.10 — общая сумма = стоимость блюд + комиссия. Формула комиссии повторена, т.к. GENERATED-колонка не может ссылаться на другую GENERATED. На ней `CHECK (total_amount >= 1000)` и составной FK из `payment` |
| `review` | `product_id`, `restaurant_id` | `GENERATED ALWAYS AS (CASE WHEN entity_type = ... THEN entity_id END) STORED` | BR-9.2 — служебные колонки для составных FK -ловушка 4 |

---

## Нормализация (3НФ)

```
Все неключевые атрибуты зависят от полного PK: в таблицах с составным ключом
(client_address, order_structure, courier_pay) нет атрибутов, зависящих от части ключа (2НФ).
Транзитивных зависимостей нет, кроме особых случаев ниже, которые оставлены осознанно,
потому что их требуют BR, а согласованность обеспечена СУБД (3НФ). Бизнес-правила важнее нормализации.

Особые случаи:
- order.commission = 10% от order_amount (BR-1.4) - транзитивная зависимость
  order_id -> order_amount -> commission. Колонка оставлена, потому что BR-7.10 требует, чтобы
  "у заказа была" комиссия, и сделана GENERATED ALWAYS .
- order.total_amount = order_amount + commission (BR-7.10) - то же самое, GENERATED ALWAYS ... STORED.
- order.order_amount - стоимость блюд, хранится как снимок на момент заказа: цена блюда в product
  может поменяться, а история заказов (и комиссии для зарплаты курьеров, BR-10.2) меняться не должна.
- order.pay_status - агрегат по попыткам оплаты (BR-7.8, BR-8.7), поддерживается триггером
  payment_update_order_pay_status при любом изменении payment.
- payment.amount = order.total_amount (BR-8.4) - дублирование между таблицами, согласованность
  обеспечивает составной FK payment_amount_matches_order.
- product.rating и restaurant.rating - агрегаты по отзывам (BR-9.6), поддерживаются триггером
  rating_change на INSERT/UPDATE/DELETE в review (BR-9.7). Осознанная денормализация для скорости
  чтения: рейтинг читается часто (меню, статистика), а пересчитывать среднее по всем отзывам при
  каждом чтении долго.
- review.client_id - формально зависит от order_id (у заказа один клиент), т.е. транзитивная
  зависимость. Поле есть в ERD (CLIENT ||--o{ REVIEW), убирать его нельзя; составной FK
  review_client_of_order не дает записать чужого клиента, поэтому аномалий нет.
- review.entity_id + entity_type - полиморфизм. 3НФ не нарушает (entity_id зависит от review_id),
  но не позволяет обычный FK - решено через вычисляемые колонки и составные FK (ловушка 4).
```

---

## Типы данных (BR-11.6)

| Колонки | Тип | Почему |
|---|---|---|
| `login` | `varchar(50)` | логин думаю 50 символов хватит |
| `password` | `varchar(32)` | BR-2.3 — хранится MD5, а MD5 строкой всегда 32 символа |
| `phone_number` | `char(12)` | в заданной схеме тип `char`, формат `+7` и 10 цифр — всегда 12 символов |
| `street`, `restaurant_name`, `product_name`, `fio` | `varchar(150)` | с запасом для длинных названий и ФИО |
| `house_number`, `apartment_office` | `varchar(20)` | бывает «12к3с1» или «офис 405», поэтому строка |
| `product_category_name` | `varchar(100)` | название категории короткое |
| `transaction_id` | `varchar(20)` | формат задает платежный провайдер (BR-8.3), 20 символов думаю достаточно, могут быть нетолько числа, но и символы |
| `description`, `company_details`, `photo_url` | `text` | длину текста и ссылки заранее не ограничить |
| `price`, `order_amount`, `commission`, `total_amount`, `payment.amount`, `courier_pay.amount` | `numeric(12,2)` | деньги: копейки, без ошибок округления float. Тип `payment.amount` совпадает с `order.total_amount` — иначе составной FK не создается |
| `product.rating`, `restaurant.rating`, `review.rating` | `numeric(2,1)` | рейтинг с одним знаком после запятой  |
| `coefficient`, `coefficient_used` | `numeric(3,2)` | значения 0.10–0.50 |
| `quantity` | `numeric(10,3)` | BR-7.15 — может быть дробным (0.5 кг), 3 знака для грамм |
| `year`, `month` | `int` | как в в заданной схеме (ERD файл) |
| все даты и время | `timestamp`, `date`, `time` без часового пояса | BR-11.2 — время в часовом поясе сервера |
