-- FOOD-106. Статистика по ресторанам
BEGIN;
CREATE OR REPLACE FUNCTION vizgaleva_food.get_statistic()
RETURNS TABLE (
    restaurant_name   varchar,
    best_product_name varchar,
    total_amount      numeric,
    avg_amount        numeric,
    best_user         varchar
)
LANGUAGE sql VOLATILE AS $$     -- VOLATILE, потому что внутри random() для выбора при равенстве
    WITH delivered AS MATERIALIZED (  
         -- таблица order читается один раз (CTE delivered с MATERIALIZED),
        -- доставленные заказы, order читается один раз
        SELECT o.order_id, o.restaurant_id, o.client_id, o.total_amount
          FROM vizgaleva_food."order" o
         WHERE o.status = 'доставлен'
    ),
    rest_client AS (
        -- сколько доставленных заказов и на какую сумму у каждого клиента в каждом ресторане
        SELECT d.restaurant_id, d.client_id, count(*) AS cnt, sum(d.total_amount) AS amount
          FROM delivered d
         GROUP BY d.restaurant_id, d.client_id
    ),
    rest_total AS (
        -- итог по ресторану из той же группировки (сумма сумм и сумма количеств)
        SELECT rc.restaurant_id,
               sum(rc.amount)                          AS total_amount,
               round(sum(rc.amount) / sum(rc.cnt), 2)  AS avg_amount
          FROM rest_client rc
         GROUP BY rc.restaurant_id
    ),
    best_client AS (
        -- клиент с наибольшим числом заказов, при равенстве случайный
        SELECT DISTINCT ON (rc.restaurant_id) rc.restaurant_id, rc.client_id
          FROM rest_client rc
         ORDER BY rc.restaurant_id, rc.cnt DESC, random()
    ),
    rest_product AS (
        -- сколько единиц каждого блюда продано в доставленных заказах ресторана
        SELECT d.restaurant_id, s.product_id, sum(s.quantity) AS qty
          FROM delivered d
          JOIN vizgaleva_food.order_structure s ON s.order_id = d.order_id
         GROUP BY d.restaurant_id, s.product_id
    ),
    best_product AS (
        -- блюдо с наибольшим количеством, при равенстве случайное
        SELECT DISTINCT ON (rp.restaurant_id) rp.restaurant_id, rp.product_id
          FROM rest_product rp
         ORDER BY rp.restaurant_id, rp.qty DESC, random()
    )
    SELECT r.restaurant_name,
           p.product_name,
           coalesce(t.total_amount, 0),
           coalesce(t.avg_amount, 0),
           c.login
      FROM vizgaleva_food.restaurant r
      LEFT JOIN rest_total   t  ON t.restaurant_id  = r.restaurant_id
      LEFT JOIN best_product bp ON bp.restaurant_id = r.restaurant_id
      LEFT JOIN vizgaleva_food.product p ON p.product_id = bp.product_id
      LEFT JOIN best_client  bc ON bc.restaurant_id = r.restaurant_id
      LEFT JOIN vizgaleva_food.client  c ON c.client_id  = bc.client_id
     ORDER BY r.restaurant_name;
$$;

COMMIT;
