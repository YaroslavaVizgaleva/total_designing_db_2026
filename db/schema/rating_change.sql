-- FOOD-105. Триггер пересчёта рейтинга
BEGIN;
CREATE OR REPLACE FUNCTION vizgaleva_food.rating_change() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP IN ('UPDATE', 'DELETE') THEN
        IF OLD.entity_type = 'блюдо' THEN
            UPDATE vizgaleva_food.product
               SET rating = (SELECT round(avg(r.rating), 1)
                               FROM vizgaleva_food.review r
                              WHERE r.entity_type = 'блюдо' AND r.entity_id = OLD.entity_id)
             WHERE product_id = OLD.entity_id;
        ELSIF OLD.entity_type = 'ресторан' THEN
            UPDATE vizgaleva_food.restaurant
               SET rating = (SELECT round(avg(r.rating), 1)
                               FROM vizgaleva_food.review r
                              WHERE r.entity_type = 'ресторан' AND r.entity_id = OLD.entity_id)
             WHERE restaurant_id = OLD.entity_id;
        END IF;
    END IF;

    IF TG_OP = 'INSERT'
       OR (TG_OP = 'UPDATE' AND (NEW.entity_type, NEW.entity_id) IS DISTINCT FROM (OLD.entity_type, OLD.entity_id)) THEN
        IF NEW.entity_type = 'блюдо' THEN
            UPDATE vizgaleva_food.product
               SET rating = (SELECT round(avg(r.rating), 1)
                               FROM vizgaleva_food.review r
                              WHERE r.entity_type = 'блюдо' AND r.entity_id = NEW.entity_id)
             WHERE product_id = NEW.entity_id;
        ELSIF NEW.entity_type = 'ресторан' THEN
            UPDATE vizgaleva_food.restaurant
               SET rating = (SELECT round(avg(r.rating), 1)
                               FROM vizgaleva_food.review r
                              WHERE r.entity_type = 'ресторан' AND r.entity_id = NEW.entity_id)
             WHERE restaurant_id = NEW.entity_id;
        END IF;
    END IF;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS rating_change ON vizgaleva_food.review;
CREATE TRIGGER rating_change
    AFTER INSERT OR DELETE OR UPDATE OF entity_type, entity_id, rating
    ON vizgaleva_food.review
    FOR EACH ROW
    EXECUTE FUNCTION vizgaleva_food.rating_change();

COMMIT;
