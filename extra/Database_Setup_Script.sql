-- ============================================================
-- BLOCK 1 OF 9 : DATABASE SETUP
-- ============================================================
-- Creates schema and loads all 8 raw Olist CSVs via LOAD DATA LOCAL INFILE.
-- DROP TABLE IF EXISTS before every CREATE TABLE prevents silent data duplication on re-runs.
-- Row count validated against known dataset row counts after every load.
--
-- NOTE: Update file paths to match local directory before running.
-- ============================================================

CREATE SCHEMA IF NOT EXISTS _olist_dataset;
USE _olist_dataset;

SET GLOBAL local_infile = 1;

-- I. olist_customers_dataset
DROP TABLE IF EXISTS olist_customers_dataset;
CREATE TABLE olist_customers_dataset (
    customer_id              VARCHAR(50),
    customer_unique_id       VARCHAR(50),
    customer_zip_code_prefix VARCHAR(10),
    customer_city            VARCHAR(25),
    customer_state           VARCHAR(5)
);
LOAD DATA LOCAL INFILE './sources/olist_customers_dataset.csv'
INTO TABLE olist_customers_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 99441 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 99441 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_customers_dataset;


-- II. olist_geolocation_dataset
DROP TABLE IF EXISTS olist_geolocation_dataset;
CREATE TABLE olist_geolocation_dataset (
    geolocation_zip_code_prefix VARCHAR(10),
    geolocation_lat             DECIMAL(23,20),
    geolocation_lng             DECIMAL(23,20),
    geolocation_city            VARCHAR(30),
    geolocation_state           VARCHAR(5)
);
LOAD DATA LOCAL INFILE './sources/olist_geolocation_dataset.csv'
INTO TABLE olist_geolocation_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 1000163 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 1000163 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_geolocation_dataset;


-- III. olist_order_items_dataset
DROP TABLE IF EXISTS olist_order_items_dataset;
CREATE TABLE olist_order_items_dataset (
    order_id            VARCHAR(50),
    order_item_id       INT,
    product_id          VARCHAR(50),
    seller_id           VARCHAR(50),
    shipping_limit_date VARCHAR(20),
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2)
);
LOAD DATA LOCAL INFILE './sources/olist_order_items_dataset.csv'
INTO TABLE olist_order_items_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 112650 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 112650 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_order_items_dataset;


-- IV. olist_order_payments_dataset
DROP TABLE IF EXISTS olist_order_payments_dataset;
CREATE TABLE olist_order_payments_dataset (
    order_id             VARCHAR(50),
    payment_sequential   INT,
    payment_type         VARCHAR(20),
    payment_installments INT,
    payment_value        DECIMAL(10,2)
);
LOAD DATA LOCAL INFILE './sources/olist_order_payments_dataset.csv'
INTO TABLE olist_order_payments_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 103886 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 103886 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_order_payments_dataset;


-- V. olist_order_reviews_dataset
DROP TABLE IF EXISTS olist_order_reviews_dataset;
CREATE TABLE olist_order_reviews_dataset (
    review_id               VARCHAR(50),
    order_id                VARCHAR(50),
    review_score            INT,
    review_comment_title    VARCHAR(100),
    review_comment_message  VARCHAR(500),
    review_creation_date    VARCHAR(20),
    review_answer_timestamp VARCHAR(20)
);
LOAD DATA LOCAL INFILE './sources/olist_order_reviews_dataset.csv'
INTO TABLE olist_order_reviews_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 99224 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 99224 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_order_reviews_dataset;


-- VI. olist_orders_dataset
DROP TABLE IF EXISTS olist_orders_dataset;
CREATE TABLE olist_orders_dataset (
    order_id                      VARCHAR(50),
    customer_id                   VARCHAR(50),
    order_status                  VARCHAR(20),
    order_purchase_timestamp      VARCHAR(20),
    order_approved_at             VARCHAR(20),
    order_delivered_carrier_date  VARCHAR(20),
    order_delivered_customer_date VARCHAR(20),
    order_estimated_delivery_date VARCHAR(20)
);
LOAD DATA LOCAL INFILE './sources/olist_orders_dataset.csv'
INTO TABLE olist_orders_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 99441 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 99441 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_orders_dataset;


-- VII. olist_products_dataset
-- Empty fields in the CSV are mapped to NULL via @variable + NULLIF.
DROP TABLE IF EXISTS olist_products_dataset;
CREATE TABLE olist_products_dataset (
    product_id                 VARCHAR(50),
    product_category_name      VARCHAR(50),
    product_name_length        INT,
    product_description_length INT,
    product_photos_qty         INT,
    product_weight_g           DECIMAL(10,2),
    product_length_cm          DECIMAL(10,2),
    product_height_cm          DECIMAL(10,2),
    product_width_cm           DECIMAL(10,2)
);
LOAD DATA LOCAL INFILE './sources/olist_products_dataset.csv'
INTO TABLE olist_products_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES
(
    @product_id,
    @product_category_name,
    @product_name_length,
    @product_description_length,
    @product_photos_qty,
    @product_weight_g,
    @product_length_cm,
    @product_height_cm,
    @product_width_cm
)
SET
    product_id                 = NULLIF(@product_id, ''),
    product_category_name      = NULLIF(@product_category_name, ''),
    product_name_length        = NULLIF(@product_name_length, ''),
    product_description_length = NULLIF(@product_description_length, ''),
    product_photos_qty         = NULLIF(@product_photos_qty, ''),
    product_weight_g           = NULLIF(@product_weight_g, ''),
    product_length_cm          = NULLIF(@product_length_cm, ''),
    product_height_cm          = NULLIF(@product_height_cm, ''),
    product_width_cm           = NULLIF(@product_width_cm, '');

SELECT 32951 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 32951 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_products_dataset;


-- VIII. olist_sellers_dataset
DROP TABLE IF EXISTS olist_sellers_dataset;
CREATE TABLE olist_sellers_dataset (
    seller_id              VARCHAR(50),
    seller_zip_code_prefix VARCHAR(10),
    seller_city            VARCHAR(25),
    seller_state           VARCHAR(5)
);
LOAD DATA LOCAL INFILE './sources/olist_sellers_dataset.csv'
INTO TABLE olist_sellers_dataset
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 LINES;

SELECT 3095 AS expected, COUNT(*) AS actual,
    CASE WHEN COUNT(*) = 3095 THEN 'PASS' ELSE 'FAIL' END AS status
FROM olist_sellers_dataset;