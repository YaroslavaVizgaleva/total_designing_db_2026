
BEGIN;

CREATE SCHEMA IF NOT EXISTS vizgaleva_food;


CREATE TYPE vizgaleva_food.restaurant_status   AS ENUM ('активен', 'неактивен'); -- BR-4.3.
CREATE TYPE vizgaleva_food.courier_status      AS ENUM ('свободен', 'занят', 'на_доставке', 'уволен'); -- BR-6.2. 
CREATE TYPE vizgaleva_food.product_status      AS ENUM ('доступно', 'нет_в_наличии', 'архив'); --BR-5.5.
CREATE TYPE vizgaleva_food.order_status        AS ENUM ('создан', 'готовится', 'в_доставке', 'доставлен','отменён'); --BR-7.7
CREATE TYPE vizgaleva_food.order_pay_status    AS ENUM ('ожидает', 'оплачен', 'ошибка'); --BR-7.9.
CREATE TYPE vizgaleva_food.review_entity_type  AS ENUM ('блюдо', 'ресторан', 'заказ'); --BR-9.1
CREATE TYPE vizgaleva_food.payment_type        AS ENUM ('карта', 'наличные', 'безнал'); --BR-8.2.
CREATE TYPE vizgaleva_food.payment_status      AS ENUM ('успех', 'ошибка', 'в_обработке'); --BR-8.2.

-- Клиент сервиса
CREATE TABLE vizgaleva_food.client (
    client_id     uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    login         varchar(50) NOT NULL UNIQUE,      -- BR-2.1., BR-2.2.
    password      varchar(32) NOT NULL,         -- BR-2.1., BR-2.3. MD5 это 32 символа
    phone_number  char(12) NOT NULL UNIQUE     -- BR-2.1., BR-2.2. 12 (+7 и 10 цифр)
);

-- Физический адрес
CREATE TABLE vizgaleva_food.address (
    address_id        uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    street            varchar(150) NOT NULL,     -- BR-3.1.
    house_number      varchar(20) NOT NULL,      -- BR-3.1.
    apartment_office  varchar(20),            -- BR-3.2. может быть пустым (частный дом)
    CONSTRAINT address_restoran_key
        UNIQUE NULLS NOT DISTINCT (street, house_number, apartment_office)-- BR-3.3. один физический адрес = одна строка, иначе два ресторана могли бы взять одинаковый адрес с разными address_id
);

-- связь многие ко многим между клиентами и адресами
CREATE TABLE vizgaleva_food.client_address (
    client_id   uuid NOT NULL
        REFERENCES vizgaleva_food.client(client_id) ON DELETE CASCADE,       -- BR-3.5. удаляется только привязка, адрес остается
    address_id  uuid NOT NULL
        REFERENCES vizgaleva_food.address(address_id) ON DELETE RESTRICT,    -- BR-3.5.
    PRIMARY KEY (client_id, address_id)     -- BR-2.4., BR-2.5. один адрес к клиенту только один раз
);

-- Ресторан-партнёр
CREATE TABLE vizgaleva_food.restaurant (
    restaurant_id    uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    restaurant_name  varchar(150) NOT NULL,                  -- BR-4.1.
    address_id       uuid NOT NULL UNIQUE REFERENCES vizgaleva_food.address(address_id) ON DELETE RESTRICT,   -- BR-3.3., BR-3.4., BR-3.5.
    description      text NOT NULL,                          -- BR-4.1.
    work_start       time NOT NULL,                          -- BR-4.4.
    work_end         time NOT NULL,                          -- BR-4.4.
    company_details  text NOT NULL,                          -- BR-4.1., BR-4.5. ИНН, ОГРН, расчетный счет
    rating           numeric(2,1),                           -- BR-4.1. пустой пока нет отзывов (BR-9.7.)
    status           vizgaleva_food.restaurant_status NOT NULL,   -- BR-4.1., BR-4.3.
    CONSTRAINT restaurant_rating_check CHECK (rating BETWEEN 0 AND 5),        -- BR-4.2.
    CONSTRAINT restaurant_work_time_check CHECK (work_end > work_start)       -- BR-4.4.
);

-- Курьер
CREATE TABLE vizgaleva_food.courier (
    courier_id      uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    fio             varchar(150) NOT NULL,                      -- BR-6.1.
    phone_number    char(12) NOT NULL,                          -- BR-6.1.
    status          vizgaleva_food.courier_status NOT NULL,     -- BR-6.1., BR-6.2.
    hire_date       date NOT NULL,                              --BR-6.1.
    dismissal_date  date,                                       -- BR-6.3. у работающего пустая
    coefficient     numeric(3,2) NOT NULL DEFAULT 0.1,             -- BR-6.1., BR-6.5. новый курьер получает 0.1
    CONSTRAINT courier_dismissal_date_check
        CHECK ((status = 'уволен') = (dismissal_date IS NOT NULL)),         -- BR-6.3., BR-11.3. уволен <=> есть дата увольнения
    CONSTRAINT courier_dismissal_after_hire_check
        CHECK (dismissal_date >= hire_date),                                -- уволить раньше найма нельзя
    CONSTRAINT courier_coefficient_check
        CHECK (coefficient BETWEEN 0.1 AND 0.5)                             -- BR-6.4. включительно
);

-- Ежемесячная выплата курьеру
CREATE TABLE vizgaleva_food.courier_pay (
    year              int NOT NULL,
    month             int NOT NULL,
    courier_id        uuid NOT NULL REFERENCES vizgaleva_food.courier(courier_id),
    amount            numeric(12,2) NOT NULL,      -- BR-11.3.
    coefficient_used  numeric(3,2) NOT NULL,       --BR-11.3.
    PRIMARY KEY (year, month, courier_id),     -- BR-10.3. одна запись на курьера за месяц  
    CONSTRAINT courier_pay_month_check CHECK (month BETWEEN 1 AND 12)-- BR-10.3. месяц только 1-12, иначе month = 13 считался бы другим месяцем и обходил ключ
);

-- Категория блюд
CREATE TABLE vizgaleva_food.product_category (
    product_category_id    uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   --BR-11.1.
    product_category_name  varchar(100) NOT NULL UNIQUE      --BR-5.7. справочник, название не повторяется
);

-- Блюдо
CREATE TABLE vizgaleva_food.product (
    product_id           uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    product_name         varchar(150) NOT NULL,                                 -- BR-5.2.
    product_category_id  uuid NOT NULL REFERENCES vizgaleva_food.product_category(product_category_id),   -- BR-5.1.
    price                numeric(12,2) NOT NULL,                                 -- BR-5.2.
    restaurant_id        uuid NOT NULL REFERENCES vizgaleva_food.restaurant(restaurant_id),             -- BR-5.1.
    photo_url            text,                                               -- BR-5.6. может быть пустым
    rating               numeric(2,1),                                       -- BR-5.2. пустой пока нет отзывов (BR-9.7.)
    status               vizgaleva_food.product_status NOT NULL,             --BR-5.2., BR-5.5.
    description          text NOT NULL,                                      --BR-5.2.
    CONSTRAINT product_price_check  CHECK (price >= 0),                      --BR-5.3.
    CONSTRAINT product_rating_check CHECK (rating BETWEEN 0 AND 5),          -- BR-5.4.
    CONSTRAINT product_photo_url_check CHECK (photo_url ~ '^https?://')      -- BR-5.6. ссылка должна начинаться с http:// или https://
);

-- Заказ
CREATE TABLE vizgaleva_food."order" (
    order_id            uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   --BR-11.1.
    courier_id          uuid NOT NULL REFERENCES vizgaleva_food.courier(courier_id),         -- BR-1.1., BR-1.3.
    client_id           uuid NOT NULL REFERENCES vizgaleva_food.client(client_id),           -- BR-1.1.
    address_id          uuid NOT NULL REFERENCES vizgaleva_food.address(address_id) ON DELETE RESTRICT,   -- BR-1.3., BR-3.5.
    restaurant_id       uuid NOT NULL REFERENCES vizgaleva_food.restaurant(restaurant_id),   -- BR-1.1.
    order_timestamp     timestamp NOT NULL,                                     -- BR-7.1., BR-7.12.
    delivery_timestamp  timestamp,                                              -- BR-7.12. пустое пока не доставлен
    order_amount        numeric(12,2) NOT NULL,                                     -- BR-7.10. стоимость блюд
    commission          numeric(12,2) GENERATED ALWAYS AS (round(order_amount * 0.10, 2)) STORED,                 -- BR-1.4., BR-7.10.
    total_amount        numeric(12,2) GENERATED ALWAYS AS (order_amount + round(order_amount * 0.10, 2)) STORED,  -- BR-7.10.
    status              vizgaleva_food.order_status NOT NULL,                   -- BR-7.6., BR-7.7.
    pay_status          vizgaleva_food.order_pay_status NOT NULL DEFAULT 'ожидает',   -- BR-7.8., BR-7.9., BR-8.7. считается триггером по оплатам
    description         text NOT NULL,                                          -- BR-11.3. правила что может быть пустым нет
    CHECK (total_amount >= 1000),   -- BR-1.8., BR-7.11. минимальная сумма заказа
    -- BR-7.4. адрес доставки должен быть одним из адресов этого клиента
    -- пара (client_id, address_id) должна быть в client_address
    CONSTRAINT order_address_belongs_to_client
        FOREIGN KEY (client_id, address_id)
        REFERENCES vizgaleva_food.client_address(client_id, address_id)
        ON DELETE RESTRICT,
    -- BR-7.12., BR-11.3. доставлен <=> есть время окончания доставки
    CONSTRAINT order_delivery_consistency
        CHECK ((status = 'доставлен') = (delivery_timestamp IS NOT NULL)),
    -- BR-7.13. доставка не может закончиться раньше создания заказа
    CONSTRAINT order_delivery_after_create_check
        CHECK (delivery_timestamp >= order_timestamp),
    -- BR-8.4. нужен для составного внешнего ключа из payment (order_id, amount)
    -- order_id и так уникальный, но внешний ключ может ссылаться только на UNIQUE или PRIMARY KEY
    CONSTRAINT order_id_total_amount_unique
        UNIQUE (order_id, total_amount),
    -- BR-9.2. нужны для составных внешних ключей из review (клиент и ресторан этого заказа)
    CONSTRAINT order_id_client_unique
        UNIQUE (order_id, client_id),
    CONSTRAINT order_id_restaurant_unique
        UNIQUE (order_id, restaurant_id)
);

-- Попытка оплаты заказа 
CREATE TABLE vizgaleva_food.payment (
    payment_id             uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    order_id               uuid NOT NULL REFERENCES vizgaleva_food."order"(order_id),   -- BR-8.1.
    payment_type           vizgaleva_food.payment_type NOT NULL,     -- BR-8.2., BR-8.6. тип у попытки, а не у заказа
    amount                 numeric(12,2) NOT NULL,                       -- BR-8.2.
    transaction_id         varchar(20) UNIQUE,                          -- BR-8.2., BR-8.3., BR-8.5. только id транзакции, данных карты нет; у наличных пустой
    transaction_timestamp  timestamp NOT NULL,                       -- BR-8.2.
    status                 vizgaleva_food.payment_status NOT NULL,   -- BR-8.2.
    -- BR-1.5., BR-8.4. сумма попытки = общая сумма заказа
    -- пара (order_id, amount) должна совпадать с (order_id, total_amount) в заказе
    -- ON UPDATE RESTRICT: нельзя поменять сумму заказа если по нему уже есть оплаты
    CONSTRAINT payment_amount_matches_order
        FOREIGN KEY (order_id, amount)
        REFERENCES vizgaleva_food."order"(order_id, total_amount)
        ON UPDATE RESTRICT
        ON DELETE RESTRICT,
    
    CONSTRAINT payment_transaction_id_check
        CHECK ((payment_type = 'наличные') = (transaction_id IS NULL)), -- BR-8.2. id финансовой транзакции есть только у оплаты картой или безналом, при оплате наличными транзакции у платежного провайдера нет: карта/безнал <=> id заполнен
    CONSTRAINT payment_cash_success_check
        CHECK (payment_type <> 'наличные' OR status = 'успех') -- оплата наличными сразу успешная (деньги получены курьером)
);

-- BR-8.1. у заказа может быть только одна успешная попытка оплаты
-- уникальный индекс только по строкам со статусом 'успех'
CREATE UNIQUE INDEX payment_one_success_per_order
    ON vizgaleva_food.payment (order_id)
    WHERE status = 'успех';

-- Позиция заказа
CREATE TABLE vizgaleva_food.order_structure (
    order_id    uuid NOT NULL REFERENCES vizgaleva_food."order"(order_id),       -- BR-7.14.
    product_id  uuid NOT NULL REFERENCES vizgaleva_food.product(product_id),     -- BR-7.14.
    quantity    numeric(10,3) NOT NULL,                                              -- BR-7.14.
    PRIMARY KEY (order_id, product_id),     -- BR-7.16. одно блюдо в заказе только один раз
    CONSTRAINT order_structure_quantity_check CHECK (quantity > 0)              -- BR-7.15. может быть дробным
);

-- Отзыв клиента на блюдо, ресторан или заказ
CREATE TABLE vizgaleva_food.review (
    review_id         uuid PRIMARY KEY DEFAULT exts.uuid_generate_v4(),   -- BR-11.1.
    client_id         uuid NOT NULL REFERENCES vizgaleva_food.client(client_id),     -- BR-9.2.
    review_timestamp  timestamp NOT NULL,                                           -- BR-9.3. дата
    entity_id         uuid NOT NULL,                                                -- BR-9.1. id блюда/ресторана/заказа
    entity_type       vizgaleva_food.review_entity_type NOT NULL,                   -- BR-9.1.
    order_id          uuid NOT NULL REFERENCES vizgaleva_food."order"(order_id),    -- BR-9.2.
    description       text NOT NULL,                                                -- BR-9.3. текст
    photo_url         text,                                                         -- BR-9.3. необязательна
    rating            numeric(2,1) NOT NULL,                                           -- BR-9.3.
    -- entity_id разложенный по типам, нужно только для внешних ключей ниже
    -- заполнено только поле нужного типа, остальное NULL
    product_id        uuid GENERATED ALWAYS AS
                          (CASE WHEN entity_type = 'блюдо' THEN entity_id END) STORED,
    restaurant_id     uuid GENERATED ALWAYS AS
                          (CASE WHEN entity_type = 'ресторан' THEN entity_id END) STORED,

    CONSTRAINT review_rating_check CHECK (rating BETWEEN 1 AND 5),                  -- BR-9.4.
    -- BR-9.5. на каждый объект в рамках заказа не больше одного отзыва
    CONSTRAINT review_one_per_entity_in_order
        UNIQUE (order_id, entity_type, entity_id),
    -- BR-9.2. отзыв пишет клиент этого заказа
    CONSTRAINT review_client_of_order
        FOREIGN KEY (order_id, client_id)
        REFERENCES vizgaleva_food."order"(order_id, client_id),
    -- BR-9.2. отзыв на заказ - это отзыв на этот же заказ
    CONSTRAINT review_order_entity_check
        CHECK (entity_type <> 'заказ' OR entity_id = order_id),
    -- BR-9.2. отзыв на ресторан - только на ресторан этого заказа
    -- если restaurant_id NULL (отзыв не на ресторан), ключ не проверяется
    CONSTRAINT review_restaurant_of_order
        FOREIGN KEY (order_id, restaurant_id)
        REFERENCES vizgaleva_food."order"(order_id, restaurant_id),
    -- BR-9.2. отзыв на блюдо - только на блюдо которое есть в этом заказе
    CONSTRAINT review_product_in_order
        FOREIGN KEY (order_id, product_id)
        REFERENCES vizgaleva_food.order_structure(order_id, product_id)
);

-- BR-7.3. все блюда в заказе из ресторана заказа
-- через FOREIGN KEY не сделать, ресторан блюда лежит в product, а не в order_structure
CREATE FUNCTION vizgaleva_food.order_structure_check_restaurant() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
          FROM vizgaleva_food."order" o
          JOIN vizgaleva_food.product p ON p.restaurant_id = o.restaurant_id
         WHERE o.order_id = NEW.order_id
           AND p.product_id = NEW.product_id
    ) THEN
        RAISE EXCEPTION 'Блюдо % не из ресторана заказа %', NEW.product_id, NEW.order_id;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER order_structure_check_restaurant
    BEFORE INSERT OR UPDATE ON vizgaleva_food.order_structure
    FOR EACH ROW EXECUTE FUNCTION vizgaleva_food.order_structure_check_restaurant();

-- BR-8.7. статус оплаты заказа считается по попыткам оплаты
-- 'оплачен' - есть успешная, 'ожидает' - есть в обработке и нет успешных,
-- 'ошибка' - все попытки с ошибкой. Если попыток нет - 'ожидает'
CREATE FUNCTION vizgaleva_food.order_pay_status_recalc(p_order_id uuid) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE vizgaleva_food."order" o
       SET pay_status = CASE
               WHEN EXISTS (SELECT 1 FROM vizgaleva_food.payment p
                             WHERE p.order_id = p_order_id AND p.status = 'успех')       THEN 'оплачен'
               WHEN EXISTS (SELECT 1 FROM vizgaleva_food.payment p
                             WHERE p.order_id = p_order_id AND p.status = 'в_обработке') THEN 'ожидает'
               WHEN EXISTS (SELECT 1 FROM vizgaleva_food.payment p
                             WHERE p.order_id = p_order_id)                             THEN 'ошибка'
               ELSE 'ожидает'
           END::vizgaleva_food.order_pay_status
     WHERE o.order_id = p_order_id;
END;
$$;

CREATE FUNCTION vizgaleva_food.payment_update_order_pay_status() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    -- при удалении или переносе оплаты на другой заказ пересчитываем старый заказ
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        PERFORM vizgaleva_food.order_pay_status_recalc(OLD.order_id);
    END IF;
    IF TG_OP IN ('INSERT', 'UPDATE') THEN
        PERFORM vizgaleva_food.order_pay_status_recalc(NEW.order_id);
    END IF;
    RETURN NULL;
END;
$$;

CREATE TRIGGER payment_update_order_pay_status
    AFTER INSERT OR UPDATE OR DELETE ON vizgaleva_food.payment
    FOR EACH ROW EXECUTE FUNCTION vizgaleva_food.payment_update_order_pay_status();

COMMIT;

