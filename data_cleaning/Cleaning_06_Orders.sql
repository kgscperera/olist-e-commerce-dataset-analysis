-- ============================================================
-- BLOCK 7 OF 9 : ORDERS - STAGING AND CLEANING
-- ============================================================
-- 1. Trim whitespace and convert all 6 timestamp columns from TEXT to DATETIME into staging_1.
-- 2. Duplicate check.
-- 3. order_status distribution check.
-- 4. Date-logic sanity checks (approval before purchase; delivery before purchase).
-- 5. Orphan check: every customer_id must exist in olist_customers_dataset_staging_1.
-- 6. Add PRIMARY KEY on order_id.
-- ============================================================

USE _olist_dataset;

-- 1. Create staging_1 (trim and convert dates)

DROP TABLE IF EXISTS olist_orders_dataset_staging_1;

CREATE TABLE olist_orders_dataset_staging_1 (
    order_id                      VARCHAR(50),
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      DATETIME,
    order_approved_at             DATETIME,
    order_delivered_carrier_date  DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME
);

INSERT INTO olist_orders_dataset_staging_1
SELECT
    TRIM(order_id),
    TRIM(customer_id),
    TRIM(order_status),
    STR_TO_DATE(NULLIF(TRIM(order_purchase_timestamp),      ''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(TRIM(order_approved_at),             ''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(TRIM(order_delivered_carrier_date),  ''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(TRIM(order_delivered_customer_date), ''), '%Y-%m-%d %H:%i:%s'),
    STR_TO_DATE(NULLIF(TRIM(order_estimated_delivery_date), ''), '%Y-%m-%d %H:%i:%s')
FROM olist_orders_dataset;

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_orders_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_orders_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99441

-- Validate no non-blank order_purchase_timestamp was silently nulled by STR_TO_DATE.
SELECT 
	COUNT(*) AS purchase_timestamp_conversion_failures,
    0 as expected_value,
    CASE
		WHEN (COUNT(*) = 0) THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_orders_dataset 			AS o
JOIN 
	olist_orders_dataset_staging_1 	AS s 
ON 	o.order_id = s.order_id
WHERE 
	TRIM(o.order_purchase_timestamp) <> ''
	AND 
    s.order_purchase_timestamp IS NULL; -- expect 0

-- 2. Duplicate check on "order_id"

WITH view_duplicates_cte AS (
    SELECT *, 
    ROW_NUMBER() OVER(
		PARTITION BY 
			order_id
	) AS row_num
    FROM 
		olist_orders_dataset_staging_1
)
SELECT 
	COUNT(*) AS duplicate_count
FROM 
	view_duplicates_cte
WHERE 
	row_num > 1; -- no duplicates

-- 3. order_status distribution.

SELECT 
	order_status, 
    COUNT(*) AS row_count
FROM 
	olist_orders_dataset_staging_1
GROUP BY 
	order_status
ORDER BY 
	row_count DESC;

-- 4. Date-logic sanity checks.

-- 4.1. Approval before purchase?
SELECT 
	COUNT(*) AS approval_before_purchase,
    CASE
		WHEN (COUNT(*) = 0) THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_orders_dataset_staging_1
WHERE 
	order_approved_at IS NOT NULL
	AND 
    order_approved_at < order_purchase_timestamp; -- expect 0

-- 4.2. Delivery before purchase?
SELECT 
	0 AS expected_value,
	COUNT(*) AS delivery_before_purchase,
    CASE
		WHEN (COUNT(*) = 0) THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_orders_dataset_staging_1
WHERE 
	order_delivered_customer_date IS NOT NULL
	AND 
    order_delivered_customer_date < order_purchase_timestamp; -- expect 0

-- 5. Orphan check: every customer_id must exist in olist_customers_dataset_staging_1.

SELECT 
	0 AS expected_value,
	COUNT(*) AS orphaned_orders,
    CASE
		WHEN (COUNT(*) = 0) THEN 'PASS'
        ELSE 'FAIL'
	END as status
FROM 
	olist_orders_dataset_staging_1 		AS o
LEFT JOIN 
	olist_customers_dataset_staging_1 	AS c 
ON 	o.customer_id = c.customer_id
WHERE 
	c.customer_id IS NULL; -- expect 0

-- 6. Add PRIMARY KEY on order_id.

ALTER TABLE olist_orders_dataset_staging_1
    MODIFY COLUMN order_id VARCHAR(50) NOT NULL,
    ADD PRIMARY KEY (order_id);

WITH row_counter AS (
	SELECT
		(SELECT COUNT(*) FROM olist_orders_dataset) AS imported_row_count,
		(SELECT COUNT(*) FROM olist_orders_dataset_staging_1) AS staging_1_row_count
)
SELECT 
	imported_row_count,
    staging_1_row_count,
	CASE
		WHEN imported_row_count = staging_1_row_count THEN 'PASS'
        ELSE 'FAIL'
	END AS status
FROM
	row_counter; -- expect 99441


-- DONE