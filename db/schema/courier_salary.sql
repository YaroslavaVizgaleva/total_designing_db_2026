-- FOOD-107. Зарплата курьеров
BEGIN;
CREATE OR REPLACE PROCEDURE vizgaleva_food.courier_salary()
LANGUAGE plpgsql AS $$
DECLARE
    v_month_start  timestamp := date_trunc('month', localtimestamp);   -- время сервера (BR-11.2)
    v_month_end    timestamp := date_trunc('month', localtimestamp) + interval '1 month';
    v_year         int       := extract(year  FROM localtimestamp)::int;
    v_month        int       := extract(month FROM localtimestamp)::int;
    v_paid         int;
    v_updated      int;
BEGIN
    WITH deliveries AS (
        -- доставленные заказы за текущий месяц по каждому курьеру, order читается один раз
        SELECT o.courier_id, count(*) AS cnt, sum(o.commission) AS commission
          FROM vizgaleva_food."order" o
         WHERE o.status = 'доставлен'                                         -- BR-10.5.
           AND o.delivery_timestamp >= v_month_start
           AND o.delivery_timestamp <  v_month_end
         GROUP BY o.courier_id
    ),
    calc AS (
        -- все курьеры, у кого нет доставок - 0 заказов и 0 комиссии
        SELECT c.courier_id,
               c.dismissal_date,
               coalesce(cp.coefficient_used, c.coefficient) AS coef_used,   -- коэффициент текущего месяца
               coalesce(d.cnt, 0)                           AS cnt,
               coalesce(d.commission, 0)                    AS commission
          FROM vizgaleva_food.courier c
          LEFT JOIN deliveries d ON d.courier_id = c.courier_id
          LEFT JOIN vizgaleva_food.courier_pay cp                            -- запись, если уже считали в этом месяце
                 ON cp.courier_id = c.courier_id AND cp.year = v_year AND cp.month = v_month
    ),
    pay AS (
        INSERT INTO vizgaleva_food.courier_pay (year, month, courier_id, amount, coefficient_used)
        SELECT v_year, v_month, calc.courier_id,
               round(calc.coef_used * calc.commission, 2),                   -- BR-10.4. не отрицательная
               calc.coef_used
          FROM calc
         WHERE calc.cnt > 0                                                  -- только если есть доставленные заказы
        ON CONFLICT (year, month, courier_id) DO UPDATE                      -- повторный вызов (BR-10.3)
           SET amount           = EXCLUDED.amount,
               coefficient_used = EXCLUDED.coefficient_used
        RETURNING 1
    ),
    new_coef AS (
        -- новый коэффициент на следующий месяц, только работающим курьерам (BR-10.6)
        UPDATE vizgaleva_food.courier c
           SET coefficient = CASE
                                 WHEN calc.cnt <= 150 THEN 0.1
                                 WHEN calc.cnt <= 250 THEN 0.2
                                 WHEN calc.cnt <= 500 THEN 0.3
                                 ELSE 0.5
                             END
          FROM calc
         WHERE c.courier_id = calc.courier_id
           AND calc.dismissal_date IS NULL
        RETURNING 1
    )
    SELECT (SELECT count(*) FROM pay), (SELECT count(*) FROM new_coef)
      INTO v_paid, v_updated;

    RAISE NOTICE 'Зарплата за %.%: записей в courier_pay %, обновлено коэффициентов %',
        lpad(v_month::text, 2, '0'), v_year, v_paid, v_updated;
END;
$$;

COMMIT;
