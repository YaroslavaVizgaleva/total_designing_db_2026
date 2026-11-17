-- FOOD-104. Добавление блюда
BEGIN;

-- добавляет одно блюдо в product
-- на входе поля product кроме product_id и rating:
--   product_id генерируется через exts.uuid_generate_v4()
--    а rating у нового блюда всегда NULL, тк отзывов еще нет, а рейтинг считается только по отзывам (BR-9.6, BR-9.7)
-- photo_url необязательный (BR-5.6), остальные обязательные

-- пример:
--   CALL vizgaleva_food.add_product(
--       p_product_name        => 'Борщ',
--       p_product_category_id => '...uuid категории...',
--       p_price               => 350.00,
--       p_restaurant_id       => '...uuid ресторана...',
--       p_status              => 'доступно',
--       p_description         => 'Классический борщ со сметаной',
--       p_photo_url           => 'https://cdn.foodexpress.ru/img/borsch.jpg');

CREATE OR REPLACE PROCEDURE vizgaleva_food.add_product(
    p_product_name        varchar,
    p_product_category_id uuid,
    p_price               numeric,
    p_restaurant_id       uuid,
    p_status              vizgaleva_food.product_status,
    p_description         text,
    p_photo_url           text    DEFAULT NULL    -- BR-5.6. фото необязательно
)
LANGUAGE plpgsql AS $$
DECLARE
    v_product_id  uuid;
    v_constraint  text;
    v_column      text;
BEGIN
    IF p_restaurant_id IS NULL THEN
        RAISE EXCEPTION 'Не указан ресторан блюда (restaurant_id)'
            USING ERRCODE = 'not_null_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM vizgaleva_food.restaurant WHERE restaurant_id = p_restaurant_id) THEN
        RAISE EXCEPTION 'Ресторан с restaurant_id = % не существует', p_restaurant_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

      IF p_product_category_id IS NULL THEN
        RAISE EXCEPTION 'Не указана категория блюда (product_category_id)'
            USING ERRCODE = 'not_null_violation';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM vizgaleva_food.product_category WHERE product_category_id = p_product_category_id) THEN
        RAISE EXCEPTION 'Категория с product_category_id = % не существует', p_product_category_id
            USING ERRCODE = 'foreign_key_violation';
    END IF;

    
    BEGIN
        INSERT INTO vizgaleva_food.product
            (product_id, product_name, product_category_id, price, restaurant_id,
             photo_url, rating, status, description)
        VALUES (exts.uuid_generate_v4(), p_product_name, p_product_category_id, p_price, p_restaurant_id,
                p_photo_url, NULL, p_status, p_description)                  -- rating = NULL (BR-9.7)
        RETURNING product_id INTO v_product_id;

    EXCEPTION
        
        WHEN check_violation THEN
            GET STACKED DIAGNOSTICS v_constraint = CONSTRAINT_NAME;
            RAISE EXCEPTION '%',
                CASE v_constraint
                    WHEN 'product_price_check'     THEN format('Цена блюда не может быть отрицательной: %s (BR-5.3)', p_price)
                    WHEN 'product_photo_url_check' THEN format('Фото должно быть ссылкой, начинающейся с http:// или https://: %s (BR-5.6)', p_photo_url)
                    ELSE format('Нарушено ограничение %s таблицы product', v_constraint)
                END
                USING ERRCODE = 'check_violation';

        WHEN not_null_violation THEN
            GET STACKED DIAGNOSTICS v_column = COLUMN_NAME;
            RAISE EXCEPTION 'Не заполнено обязательное поле блюда: %', v_column
                USING ERRCODE = 'not_null_violation';

        WHEN string_data_right_truncation THEN
            RAISE EXCEPTION 'Название блюда длиннее 150 символов: %', length(p_product_name)
                USING ERRCODE = 'string_data_right_truncation';

        -- цена не помещается в numeric(12,2)
        WHEN numeric_value_out_of_range THEN
            RAISE EXCEPTION 'Слишком большая цена блюда: % (максимум 9999999999.99)', p_price
                USING ERRCODE = 'numeric_value_out_of_range';
    END;

    RAISE NOTICE 'Блюдо "%" добавлено, product_id = %', p_product_name, v_product_id;
END;
$$;

COMMIT;
