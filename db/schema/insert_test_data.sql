-- FOOD-102. Генератор тестовых данных

BEGIN;

CREATE OR REPLACE PROCEDURE vizgaleva_food.insert_test_data(value int)
LANGUAGE plpgsql AS $$
DECLARE
    -- даты: в пределах последних 180 дней и без текущего месяца (за него зарплата еще не считается)
    -- например сегодня 16 ноября -> данные с 20 мая по 31 октября 23:59:59
    v_from        timestamp := (current_date - 179)::timestamp;                            -- начало дня 179 дней назад
    v_to          timestamp := date_trunc('month', localtimestamp) - interval '1 second';  -- последняя секунда прошлого месяца
    -- месяцы выплат: 6 полных месяцев до текущего (например май - октябрь)
    v_pay_from    timestamp := date_trunc('month', localtimestamp) - interval '6 months';

    -- токен этого вызова, чтобы адреса и названия не совпали с прошлыми вызовами
    v_token       text := left(replace(exts.uuid_generate_v4()::text, '-', ''), 8);

    v_categories       uuid[] := '{}';
    v_cat_base         int[]  := '{}';
    v_rest_addresses   uuid[] := '{}';
    v_restaurants      uuid[];
    v_client_addresses uuid[] := '{}';

    -- улицы для адресов
    v_streets     text[] := ARRAY[
        'Красная', 'Ленина', 'Пушкина', 'Гимназическая', 'Гоголя', 'Красноармейская',
        'Северная', 'Ставропольская', 'Российская', 'Кубанская Набережная'];
    -- названия ресторанов
    v_rest_names  text[] := ARRAY[
        'Рётэй (Ryotei)', 'Томми Lee', 'Скотина', 'Madonna', 'Гоголь', 'Yiayia. Таверна',
        'Джимми Чу', 'Rodina южной кухни', 'Южанин', 'Хмельной Повар', 'Сгущенка', 'Зацепи',
        'Краснодарский парень', 'Бастурма', 'Sofi', 'Bésame mucho', 'Miu47', 'Каппу Ча',
        'Чик Чак', 'Пивной ресторан «Стадион №1»', 'Додо Пицца', 'Ташир Пицца', 'Кубана Toscana',
        'Уни-пицца', 'Grazie pizza', 'Луна-пицца', 'Джунгли Экспресс', 'Ёха-пицца', 'Жар-Пицца',
        'Pizza Robertino', 'Папа Джонс (Papa John''s)', 'IL Патио'];
    v_street      text;
    v_house       text;
    v_apart       text;
    v_clients          uuid[];
    v_couriers         uuid[] := '{}';
    v_cour_hire        date[] := '{}';   -- даты найма курьеров (в том же порядке, что v_couriers)
    v_cour_dism        date[] := '{}';   -- даты увольнения курьеров
    v_products         uuid[] := '{}';
    v_prod_prices      numeric[] := '{}';   -- цены блюд (в том же порядке, что v_products)

    -- справочник категорий и блюд в них
    v_cat_names   text[] := ARRAY[
        'Супы', 'Салаты', 'Закуски', 'Пицца', 'Бургеры', 'Суши и роллы', 'Паста и ризотто',
        'Гриль и шашлыки', 'Гарниры', 'Завтраки', 'Десерты', 'Напитки',
        'Вегетарианские блюда', 'Детское меню'];
    v_cat_dishes  text[] := ARRAY[
        'борщ, крем-суп, том-ям, солянка',
        'цезарь, греческий, оливье, поке',
        'наггетсы, сырные палочки, картофель фри, хумус',
        'маргарита, пепперони, четыре сыра',
        'чизбургер, чикенбургер, вегги-бургер',
        'филадельфия, калифорния, ролл с угрём',
        'карбонара, болоньезе, ризотто с грибами',
        'шашлык из курицы, люля-кебаб, стейк',
        'картофельное пюре, рис, овощи на пару',
        'омлет, сырники, каша, круассан',
        'чизкейк, тирамису, мороженое, эклер',
        'лимонад, кофе, чай, сок',
        'овощной боул, фалафель, тофу-стейк',
        'мини-бургер, куриные наггетсы, молочный коктейль'];
    v_cat_name    text;
    v_dishes      text[];
    v_n           int;
    v_c           int;
    v_phone_base  bigint;
    v_id          uuid;
    v_status      vizgaleva_food.courier_status;
    v_active_st   vizgaleva_food.courier_status[];
    v_hire        date;
    v_dismissal   date;
    v_client_idx  int;
    v_client      uuid;
    v_address     uuid;
    v_rest_idx    int;
    v_restaurant  uuid;
    v_cour_idx    int;
    v_order       uuid;
    v_order_ts    timestamp;
    v_delivery_ts timestamp;
    v_order_st    vizgaleva_food.order_status;
    v_items_cnt   int;
    v_tmp         int;
    v_items       uuid[];
    v_prices      numeric[];
    v_qty         numeric[];
    v_sum         numeric;
    v_total       numeric;
    v_attempts    int;
    v_pay_ts      timestamp;
    v_tx_id       varchar(20);
    v_pay_type    vizgaleva_food.payment_type;
    v_noncash     vizgaleva_food.payment_type[] := array_remove(enum_range(NULL::vizgaleva_food.payment_type), 'наличные');
    v_entity_type vizgaleva_food.review_entity_type;
    v_entity_id   uuid;
    v_rec         record;
    v_prev        uuid;
    v_coef        numeric;
    v_last_names  text[] := ARRAY['Иванов','Петров','Сидоров','Смирнов','Кузнецов','Попов','Васильев','Соколов','Михайлов','Новиков'];
    v_first_names text[] := ARRAY['Иван','Петр','Алексей','Дмитрий','Сергей','Андрей','Михаил','Николай','Егор','Олег'];
    v_patronymics text[] := ARRAY['Иванович','Петрович','Сергеевич','Андреевич','Олегович','Дмитриевич'];
    i int;
    j int;
    k int;
BEGIN
    IF value IS NULL OR value < 1 THEN
        RAISE EXCEPTION 'value должно быть >= 1, передано %', value;
    END IF;

    -- 1. Категории N штук

    SELECT count(*) INTO v_n FROM vizgaleva_food.product_category;

    FOR i IN 1..value LOOP
        LOOP
            v_c := (v_n % array_length(v_cat_names, 1)) + 1;
            v_cat_name := v_cat_names[v_c]
                || CASE WHEN v_n >= array_length(v_cat_names, 1)
                        THEN ' ' || (v_n / array_length(v_cat_names, 1) + 1)
                        ELSE '' END;
            v_n := v_n + 1;
            EXIT WHEN NOT EXISTS (SELECT 1 FROM vizgaleva_food.product_category
                                   WHERE product_category_name = v_cat_name);   -- поиск по уникальному индексу
        END LOOP;

        INSERT INTO vizgaleva_food.product_category (product_category_id, product_category_name)
        VALUES (exts.uuid_generate_v4(), v_cat_name)
        RETURNING product_category_id INTO v_id;

        v_categories := v_categories || v_id;
        v_cat_base   := v_cat_base || v_c;
    END LOOP;


    -- 2. Адреса: N под рестораны + N*4 под клиентов (BR-11.7)

    FOR i IN 1..value * 5 LOOP
        LOOP
            v_street := v_streets[1 + floor(random() * array_length(v_streets, 1))::int];
            v_house  := (1 + floor(random() * 150))::int::text;
            IF i <= value THEN
                v_apart := CASE WHEN random() < 0.5 THEN NULL                 -- BR-3.2. может не быть
                                ELSE 'офис ' || (1 + floor(random() * 300))::int END;
            ELSE
                v_apart := CASE WHEN random() < 0.3 THEN NULL                 -- частный дом
                                ELSE 'кв. ' || (1 + floor(random() * 200))::int END;
            END IF;

            EXIT WHEN NOT EXISTS (
                SELECT 1 FROM vizgaleva_food.address
                 WHERE street = v_street
                   AND house_number = v_house
                   AND apartment_office IS NOT DISTINCT FROM v_apart);        -- NULL = NULL как в NULLS NOT DISTINCT
        END LOOP;

        INSERT INTO vizgaleva_food.address (address_id, street, house_number, apartment_office)
        VALUES (exts.uuid_generate_v4(), v_street, v_house, v_apart)
        RETURNING address_id INTO v_id;

        IF i <= value THEN
            v_rest_addresses := v_rest_addresses || v_id;
        ELSE
            v_client_addresses := v_client_addresses || v_id;
        END IF;
    END LOOP;


    -- 3. Рестораны: N шт, у каждого свой адрес (BR-3.3)

    WITH ins AS (
        INSERT INTO vizgaleva_food.restaurant
            (restaurant_id, restaurant_name, address_id, description, work_start, work_end,
             company_details, rating, status)
        SELECT exts.uuid_generate_v4(),
               v_rest_names[1 + floor(random() * array_length(v_rest_names, 1))::int],   -- случайное из списка
               a.address_id,
               'Описание ресторана ' || a.n,
               time '08:00' + (floor(random() * 4) * interval '1 hour'),      -- открытие 08:00 - 11:00
               time '20:00' + (floor(random() * 4) * interval '1 hour'),      -- закрытие 20:00 - 23:00, позже открытия (BR-4.4)
               'ИНН ' || lpad((floor(random() * 1e10))::bigint::text, 10, '0')
                   || ', ОГРН ' || lpad((floor(random() * 1e13))::bigint::text, 13, '0'),
               NULL,
               (enum_range(NULL::vizgaleva_food.restaurant_status))
                   [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.restaurant_status)))::int]
          FROM unnest(v_rest_addresses) WITH ORDINALITY AS a(address_id, n)
         ORDER BY a.n
        RETURNING restaurant_id
    )
    SELECT array_agg(restaurant_id) INTO v_restaurants FROM ins;


    -- 4. Блюда: N*5 шт, по 5 на каждый ресторан


    FOR i IN 1..value * 5 LOOP
        v_c      := 1 + floor(random() * value)::int;
        v_dishes := string_to_array(v_cat_dishes[v_cat_base[v_c]], ', ');
        v_cat_name := v_dishes[1 + floor(random() * array_length(v_dishes, 1))::int];

        INSERT INTO vizgaleva_food.product
            (product_id, product_name, product_category_id, price, restaurant_id,
             photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(),
                upper(left(v_cat_name, 1)) || substr(v_cat_name, 2),
                v_categories[v_c],
                round((300 + random() * 1200)::numeric, 2),
                v_restaurants[((i - 1) % value) + 1],
                CASE WHEN random() < 0.3 THEN NULL
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
                NULL,
                (enum_range(NULL::vizgaleva_food.product_status))
                    [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.product_status)))::int],
                'Описание блюда ' || i)
        RETURNING product_id, price INTO v_id, v_sum;

        v_products    := v_products || v_id;
        v_prod_prices := v_prod_prices || v_sum;
    END LOOP;


    -- 5. Клиенты: N шт. Логин и телефон уникальные (BR-2.2)

    SELECT coalesce(max(substr(phone_number, 3)::bigint), 9000000000)
      INTO v_phone_base
      FROM vizgaleva_food.client;

    WITH ins AS (
        INSERT INTO vizgaleva_food.client (client_id, login, password, phone_number)
        SELECT exts.uuid_generate_v4(),
               'user_' || v_token || '_' || g,
               md5(random()::text),
               '+7' || (v_phone_base + g)::text
          FROM generate_series(1, value) g
         ORDER BY g
        RETURNING client_id
    )
    SELECT array_agg(client_id) INTO v_clients FROM ins;


    -- 6. client_address: у каждого клиента по 4 своих адреса

    INSERT INTO vizgaleva_food.client_address (client_id, address_id)
    SELECT v_clients[((a.n - 1) % value) + 1], a.address_id
      FROM unnest(v_client_addresses) WITH ORDINALITY AS a(address_id, n);


    -- 7. Курьеры: N шт

    SELECT coalesce(max(substr(phone_number, 3)::bigint), 8000000000)
      INTO v_phone_base
      FROM vizgaleva_food.courier;

    v_active_st := array_remove(enum_range(NULL::vizgaleva_food.courier_status), 'уволен');

    FOR i IN 1..value LOOP
        IF i = 1 THEN
            v_hire   := v_from::date;
            v_status := v_active_st[1 + floor(random() * cardinality(v_active_st))::int];
        ELSE
            v_hire   := v_from::date + floor(random() * 28)::int;
            v_status := (enum_range(NULL::vizgaleva_food.courier_status))
                            [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.courier_status)))::int];
        END IF;

        -- BR-6.3. уволен <=> есть дата увольнения, дата не раньше найма и не позже конца окна
        IF v_status = 'уволен' THEN
            v_dismissal := v_hire + 30 + floor(random() * (v_to::date - v_hire - 30 + 1))::int;
        ELSE
            v_dismissal := NULL;
        END IF;

        INSERT INTO vizgaleva_food.courier
            (courier_id, fio, phone_number, status, hire_date, dismissal_date, coefficient)
        VALUES (exts.uuid_generate_v4(),
                v_last_names[1 + floor(random() * array_length(v_last_names, 1))::int] || ' ' ||
                v_first_names[1 + floor(random() * array_length(v_first_names, 1))::int] || ' ' ||
                v_patronymics[1 + floor(random() * array_length(v_patronymics, 1))::int],
                '+7' || (v_phone_base + i)::text,
                v_status, v_hire, v_dismissal,
                0.1)
        RETURNING courier_id INTO v_id;

        v_couriers  := v_couriers  || v_id;
        v_cour_hire := v_cour_hire || v_hire;
        v_cour_dism := v_cour_dism || v_dismissal;
    END LOOP;


    -- 8. Заказы, позиции, оплаты и отзывы: заказов и отзывов N*5
    -- все случайные id берутся из массивов, без SELECT ... ORDER BY random() в цикле

    FOR k IN 1..value * 5 LOOP
        -- клиент по кругу, адрес - один из его 4 адресов (BR-7.4)
        v_client_idx := ((k - 1) % value) + 1;
        v_client     := v_clients[v_client_idx];
        v_address    := v_client_addresses[v_client_idx + floor(random() * 4)::int * value];

        v_rest_idx   := 1 + floor(random() * value)::int;
        v_restaurant := v_restaurants[v_rest_idx];
        v_order_ts   := v_from + random() * (v_to - v_from - interval '1 hour');

        -- курьер, который работал в день заказа: пробуем случайных, если не нашли - первый (он работает всегда)
        v_cour_idx := 1;
        FOR j IN 1..20 LOOP
            v_tmp := 1 + floor(random() * value)::int;
            IF v_cour_hire[v_tmp] <= v_order_ts::date
               AND (v_cour_dism[v_tmp] IS NULL OR v_cour_dism[v_tmp] >= v_order_ts::date) THEN
                v_cour_idx := v_tmp;
                EXIT;
            END IF;
        END LOOP;

        -- 1-5 разных блюд этого ресторана (BR-7.3, BR-7.16)

        v_items_cnt := 1 + floor(random() * 5)::int;                        -- сколько блюд будет в заказе

        v_items := '{}'; v_prices := '{}'; v_qty := '{}';
        WHILE cardinality(v_items) < v_items_cnt LOOP
            -- случайное блюдо ресторана
            v_tmp := v_rest_idx + floor(random() * 5)::int * value;

            -- такое блюдо уже есть в заказе - пропускаем (BR-7.16)
            CONTINUE WHEN v_products[v_tmp] = ANY (v_items);

            v_items  := v_items  || v_products[v_tmp];
            v_prices := v_prices || v_prod_prices[v_tmp];
            v_qty    := v_qty    || (1 + floor(random() * 3))::numeric;     -- количество 1-3 (BR-7.15)
        END LOOP;

        -- общая сумма не меньше 1000 (BR-7.11): если не хватает, добавляем первое блюдо
        LOOP
            SELECT sum(pr * q) INTO v_sum FROM unnest(v_prices, v_qty) AS t(pr, q);
            v_sum := round(v_sum, 2);
            EXIT WHEN v_sum + round(v_sum * 0.10, 2) >= 1000;
            v_qty[1] := v_qty[1] + 1;
        END LOOP;

        v_order_st := (enum_range(NULL::vizgaleva_food.order_status))
                          [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.order_status)))::int];
        IF v_order_st = 'доставлен' THEN
            v_delivery_ts := least(v_order_ts + (20 + random() * 70) * interval '1 minute', v_to);   -- BR-7.13.
        ELSE
            v_delivery_ts := NULL;
        END IF;

        INSERT INTO vizgaleva_food."order"
            (order_id, courier_id, client_id, address_id, restaurant_id, order_timestamp,
             delivery_timestamp, order_amount, status, description)
        VALUES (exts.uuid_generate_v4(), v_couriers[v_cour_idx], v_client, v_address, v_restaurant, v_order_ts,
                v_delivery_ts, v_sum, v_order_st, 'Комментарий к заказу ' || k)
        RETURNING order_id, total_amount INTO v_order, v_total;

        INSERT INTO vizgaleva_food.order_structure (order_id, product_id, quantity)
        SELECT v_order, t.product_id, t.q
          FROM unnest(v_items, v_qty) AS t(product_id, q);

        -- оплаты: 1-3 попытки, последняя успешная, остальные с ошибкой (BR-8.1: ровно одна успешная)
        -- неуспешной может быть только оплата картой или безналом, наличные всегда успешные
        v_attempts := 1 + floor(random() * 3)::int;
        v_pay_ts   := v_order_ts;
        FOR j IN 1..v_attempts LOOP
            v_pay_ts := least(v_pay_ts + (1 + random() * 10) * interval '1 minute', v_to);

            -- тип оплаты: наличные всегда успешные, поэтому неуспешные попытки только картой или безналом,
            -- а последняя (успешная) - любым типом
            IF j = v_attempts THEN
                v_pay_type := (enum_range(NULL::vizgaleva_food.payment_type))
                                  [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.payment_type)))::int];
            ELSE
                v_pay_type := v_noncash[1 + floor(random() * cardinality(v_noncash))::int];
            END IF;

            -- id транзакции только у карты и безнала (BR-8.2), у наличных NULL
            IF v_pay_type = 'наличные' THEN
                v_tx_id := NULL;
            ELSE
                LOOP
                    v_tx_id := 'TX' || upper(left(replace(exts.uuid_generate_v4()::text, '-', ''), 18));
                    EXIT WHEN NOT EXISTS (SELECT 1 FROM vizgaleva_food.payment WHERE transaction_id = v_tx_id);
                END LOOP;
            END IF;

            INSERT INTO vizgaleva_food.payment
                (payment_id, order_id, payment_type, amount, transaction_id, transaction_timestamp, status)
            VALUES (exts.uuid_generate_v4(), v_order,
                    v_pay_type,
                    v_total,
                    v_tx_id,                                                 
                    v_pay_ts,
                    CASE WHEN j = v_attempts THEN 'успех' ELSE 'ошибка' END::vizgaleva_food.payment_status);
        END LOOP;

        -- один отзыв на заказ: на блюдо из заказа, на ресторан заказа или на сам заказ (BR-9.2)
        v_entity_type := (enum_range(NULL::vizgaleva_food.review_entity_type))
                             [1 + floor(random() * cardinality(enum_range(NULL::vizgaleva_food.review_entity_type)))::int];
        v_entity_id := CASE v_entity_type
                           WHEN 'блюдо'    THEN v_items[1 + floor(random() * array_length(v_items, 1))::int]
                           WHEN 'ресторан' THEN v_restaurant
                           ELSE v_order
                       END;

        INSERT INTO vizgaleva_food.review
            (review_id, client_id, review_timestamp, entity_id, entity_type, order_id,
             description, photo_url, rating)
        VALUES (exts.uuid_generate_v4(), v_client,
                least(coalesce(v_delivery_ts, v_order_ts) + random() * interval '2 days', v_to),
                v_entity_id, v_entity_type, v_order,
                'Отзыв к заказу ' || k,
                CASE WHEN random() < 0.5 THEN NULL                           -- BR-9.3. фото необязательно
                     ELSE 'https://cdn.foodexpress.ru/img/' || md5(random()::text) || '.jpg' END,
                1 + floor(random() * 5));                                    -- BR-9.4. от 1 до 5
    END LOOP;

    -- 9. Рейтинги блюд и ресторанов этого вызова по отзывам (BR-9.6)

    UPDATE vizgaleva_food.product p
       SET rating = a.avg_rating
      FROM (SELECT entity_id, round(avg(rating), 1) AS avg_rating
              FROM vizgaleva_food.review
             WHERE entity_type = 'блюдо' AND entity_id = ANY (v_products)
             GROUP BY entity_id) a
     WHERE p.product_id = a.entity_id;

    UPDATE vizgaleva_food.restaurant rs
       SET rating = a.avg_rating
      FROM (SELECT entity_id, round(avg(rating), 1) AS avg_rating
              FROM vizgaleva_food.review
             WHERE entity_type = 'ресторан' AND entity_id = ANY (v_restaurants)
             GROUP BY entity_id) a
     WHERE rs.restaurant_id = a.entity_id;

  
    -- 10. Расчет выплаты курьерам за 6 полных месяцев до текущего (BR-10.2, BR-10.7), текущий месяц не считаем
  
    v_prev := NULL;
    FOR v_rec IN
        SELECT c.courier_id,
               c.dismissal_date,
               m.month_start,
               coalesce(a.cnt, 0)  AS cnt,
               coalesce(a.comm, 0) AS comm
          FROM vizgaleva_food.courier c
         CROSS JOIN generate_series(v_pay_from, v_pay_from + interval '5 months', interval '1 month') AS m(month_start)
          LEFT JOIN (SELECT courier_id,
                            date_trunc('month', delivery_timestamp) AS month_start,
                            count(*)        AS cnt,
                            sum(commission) AS comm
                       FROM vizgaleva_food."order"
                      WHERE courier_id = ANY (v_couriers)
                        AND status = 'доставлен'                             -- BR-10.5.
                      GROUP BY 1, 2) a
                 ON a.courier_id = c.courier_id AND a.month_start = m.month_start
         WHERE c.courier_id = ANY (v_couriers)
         ORDER BY c.courier_id, m.month_start
    LOOP
        
        IF v_prev IS DISTINCT FROM v_rec.courier_id THEN
            IF v_prev IS NOT NULL THEN
                UPDATE vizgaleva_food.courier SET coefficient = v_coef WHERE courier_id = v_prev;
            END IF;
            v_prev := v_rec.courier_id;
            v_coef := 0.1;
        END IF;

        INSERT INTO vizgaleva_food.courier_pay (year, month, courier_id, amount, coefficient_used)
        VALUES (extract(year FROM v_rec.month_start)::int,
                extract(month FROM v_rec.month_start)::int,
                v_rec.courier_id,
                round(v_coef * v_rec.comm, 2),                               -- BR-10.4. не отрицательная
                v_coef);

       
        IF v_rec.dismissal_date IS NULL
           OR v_rec.dismissal_date >= (v_rec.month_start + interval '1 month')::date THEN
            v_coef := CASE
                          WHEN v_rec.cnt <= 150 THEN 0.1
                          WHEN v_rec.cnt <= 250 THEN 0.2
                          WHEN v_rec.cnt <= 500 THEN 0.3
                          ELSE 0.5
                      END;
        END IF;
    END LOOP;

    IF v_prev IS NOT NULL THEN
        UPDATE vizgaleva_food.courier SET coefficient = v_coef WHERE courier_id = v_prev;
    END IF;
END;
$$;

COMMIT;
