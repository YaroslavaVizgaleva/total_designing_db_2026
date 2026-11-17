-- FOOD-108. Отчёт «сколько денег»
BEGIN;
CREATE OR REPLACE VIEW vizgaleva_food.how_much_money AS
WITH RECURSIVE
orders_by_month AS (
    -- суммы доставленных заказов по месяцам, order читается один раз
    SELECT date_trunc('month', o.delivery_timestamp) AS month_start,
           sum(o.order_amount)                       AS sum_no_commission,
           sum(o.total_amount)                       AS sum_with_commission
      FROM vizgaleva_food."order" o
     WHERE o.status = 'доставлен'
     GROUP BY 1
),
months AS (
    -- первый месяц с доставленными заказами
    SELECT min(month_start) AS month_start
      FROM orders_by_month
    HAVING count(*) > 0
    UNION ALL
    -- следующий месяц, пока не дошли до последнего месяца с доставленными заказами
    SELECT m.month_start + interval '1 month'
      FROM months m
     WHERE m.month_start < (SELECT max(month_start) FROM orders_by_month)
),
pay_by_month AS (
    -- зарплата курьеров по месяцам
    SELECT make_date(cp.year, cp.month, 1)::timestamp AS month_start,
           sum(cp.amount)                             AS courier_pay
      FROM vizgaleva_food.courier_pay cp
     GROUP BY 1
),
report AS (
    -- месяцы без заказов или без выплат получают 0
    SELECT m.month_start,
           coalesce(o.sum_no_commission, 0)                                   AS sum_no_commission,
           coalesce(o.sum_with_commission, 0)                                 AS sum_with_commission,
           coalesce(o.sum_with_commission, 0) - coalesce(o.sum_no_commission, 0) AS commission,
           coalesce(p.courier_pay, 0)                                         AS courier_pay
      FROM months m
      LEFT JOIN orders_by_month o ON o.month_start = m.month_start
      LEFT JOIN pay_by_month    p ON p.month_start = m.month_start
)
SELECT to_char(r.month_start, 'YYYY-MM')                                   AS year_month,
       r.sum_no_commission::numeric                                         AS sum_no_commission,
       r.sum_with_commission::numeric                                       AS sum_with_commission,
       r.commission::numeric                                                AS commission,
       (lag(r.commission) OVER (ORDER BY r.month_start))::numeric           AS prev_commission,
       (r.commission - lag(r.commission) OVER (ORDER BY r.month_start))::numeric AS commission_diff,
       r.courier_pay::numeric                                               AS courier_pay,
       (r.commission - r.courier_pay)::numeric                              AS net_profit
  FROM report r
 ORDER BY r.month_start;

COMMIT;
