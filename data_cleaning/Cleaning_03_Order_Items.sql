-- =================================================================================================
-- BLOCK 4 OF 9 : ORDER ITEMS - STAGING AND CLEANING
-- =================================================================================================
-- 1. Trim whitespace into olist_order_items_dataset_staging_1.
-- 2. Duplicate check on staging_1.
-- 3. Convert shipping_limit_date from VARCHAR to DATETIME in olist_order_items_dataset_staging_2.
-- 4. Validate order_item_id is a clean per-order sequential counter.
-- 5. Add composite PRIMARY KEY (order_id, order_item_id).
-- 6. Orphan check: every order_id must exist in olist_orders_dataset.
-- =================================================================================================

USE _olist_dataset;

-- 1. Trim whitespace into olist_order_items_dataset_staging_1.

DROP TABLE IF EXISTS olist_order_items_dataset_staging_1;

CREATE TABLE olist_order_items_dataset_staging_1 (
    order_id            VARCHAR(50),
    order_item_id       INT,
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date VARCHAR(20),
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_order_items_dataset_staging_1 (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
SELECT
    TRIM(order_id),
    TRIM(order_item_id),
    TRIM(product_id),
    TRIM(seller_id),
    TRIM(shipping_limit_date),
    price,
    freight_value
FROM olist_order_items_dataset;

WITH row_counter AS (
    SELECT
        (SELECT COUNT(*) FROM olist_order_items_dataset)           AS imported_row_count,
        (SELECT COUNT(*) FROM olist_order_items_dataset_staging_1) AS staging_1_row_count
)
SELECT
    imported_row_count,
    staging_1_row_count,
    CASE 
		WHEN imported_row_count = staging_1_row_count THEN 'PASS' 
		ELSE 'FAIL' 
    END AS status
FROM 
	row_counter; -- expect 112650

-- 2. Duplicate check on staging_1

WITH view_duplicates_cte AS (
    SELECT *,
        ROW_NUMBER() OVER(
			PARTITION BY 
				order_id, 
                order_item_id, 
                product_id, 
                seller_id, price, 
                freight_value
        ) AS row_num
    FROM 
		olist_order_items_dataset_staging_1
)
SELECT 
	COUNT(*) AS duplicate_count
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1; -- NO DUPLICATES

-- 3. Create staging_2 and convert shipping_limit_date from TEXT to DATETIME.
--    	1. A new staging table is created.
-- 		2. DATETIME column is added.
--    	3. Populated the new DATETIME column via implicit string-to-datetime conversion.
--    	4. Validated the conversion.
--    	5. Replaced original TEXT column.

DROP TABLE IF EXISTS olist_order_items_dataset_staging_2;

CREATE TABLE olist_order_items_dataset_staging_2 (
    order_id            VARCHAR(50),
    order_item_id       INT,
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date VARCHAR(20),
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO olist_order_items_dataset_staging_2 (order_id, order_item_id, product_id, seller_id, shipping_limit_date, price, freight_value)
SELECT 
	order_id, 
    order_item_id, 
    product_id, 
    seller_id, 
    shipping_limit_date, 
    price, 
    freight_value
FROM 
	olist_order_items_dataset_staging_1;

ALTER TABLE olist_order_items_dataset_staging_2
	ADD COLUMN shipping_limit_date_2 DATETIME;

UPDATE olist_order_items_dataset_staging_2
    SET shipping_limit_date_2 = NULLIF(shipping_limit_date, '');

-- Validate: all three counts must equal 112650 (no NULLs introduced by conversion).
SELECT
    COUNT(*)                     AS total_rows,
    COUNT(shipping_limit_date)   AS text_column,
    COUNT(shipping_limit_date_2) AS datetime_column,
    CASE
		WHEN (COUNT(shipping_limit_date) = COUNT(shipping_limit_date_2)) THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_order_items_dataset_staging_2; -- expect 112650, 112650, 112650

ALTER TABLE olist_order_items_dataset_staging_2
	DROP COLUMN shipping_limit_date,
    CHANGE shipping_limit_date_2 shipping_limit_date DATETIME;

WITH row_counter as (
	SELECT
		(SELECT COUNT(*) FROM olist_order_items_dataset_staging_2) AS rows_before_datetime_conversion, 
		(SELECT COUNT(*) FROM olist_order_items_dataset_staging_2) AS rows_after_datetime_conversion
)
SELECT
    rows_before_datetime_conversion,
    rows_after_datetime_conversion,
    CASE 
		WHEN rows_before_datetime_conversion = rows_after_datetime_conversion THEN 'PASS' 
		ELSE 'FAIL' 
    END AS status
FROM 
	row_counter; -- expect 112650

-- 4. Validate order_item_id is a clean
-- Empty result     = clean sequence. 
-- Non-empty result = gaps or non-sequential numbering.

SELECT 
	order_id, 
	COUNT(*) AS item_count, 
    MAX(order_item_id) AS max_id
FROM 
	olist_order_items_dataset_staging_2
GROUP BY 
	order_id
HAVING 
	COUNT(*) <> MAX(order_item_id);

-- 5. Add composite PRIMARY KEY (order_id + order_item_id is the natural key).

ALTER TABLE olist_order_items_dataset_staging_2
    MODIFY COLUMN order_id VARCHAR(50) NOT NULL,
    MODIFY COLUMN order_item_id INT NOT NULL,
    ADD PRIMARY KEY (order_id, order_item_id);

-- 6. Orphan check: every order_id in staging_2 must exist in olist_orders_dataset.

SELECT 
	orphaned_order_items,
	CASE 
		WHEN orphaned_order_items = 0 THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM (
	SELECT
		COUNT(*) AS orphaned_order_items
	FROM
		olist_order_items_dataset_staging_2 AS oi
	LEFT JOIN
		olist_orders_dataset                AS o
    ON  oi.order_id = o.order_id
	WHERE
		o.order_id IS NULL
) AS sub;

-- DONE