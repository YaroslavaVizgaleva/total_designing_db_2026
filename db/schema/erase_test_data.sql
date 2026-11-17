-- FOOD-103. Удаление тестовых данных

BEGIN;

CREATE OR REPLACE PROCEDURE vizgaleva_food.erase_test_data()
LANGUAGE plpgsql AS $$
BEGIN
      DELETE FROM vizgaleva_food.review;

      DELETE FROM vizgaleva_food.payment;

      DELETE FROM vizgaleva_food.order_structure;

      DELETE FROM vizgaleva_food.courier_pay;

      DELETE FROM vizgaleva_food."order";

      DELETE FROM vizgaleva_food.client_address;

      DELETE FROM vizgaleva_food.product;

      DELETE FROM vizgaleva_food.product_category;

       DELETE FROM vizgaleva_food.restaurant;

      DELETE FROM vizgaleva_food.address;

     DELETE FROM vizgaleva_food.client;

    DELETE FROM vizgaleva_food.courier;
END;
$$;

COMMIT;
