# ============================================================
# 03. Product Category Performance
# ============================================================

# 1. Question
# Which product categories generate the most revenue?
# Which categories have the worst satisfaction-to-revenue ratio?

# 2. What I did in simple English
# Step 1 : Order count and Revenue per category.
# Step 2 : Ranked categories by revenue and by review score separately.
# Step 3 : Combined both ranks to surface categories that are high-revenue but low-rated.

# 3. Tables and Columns Used
# olist_order_items_dataset_staging_2
#   order_id, product_id, price
#
# olist_products_dataset_staging_2
#   product_id, product_category_name_english
#
# olist_order_reviews_dataset_staging_2
#   order_id, review_score, review_creation_date
#
# JOINs used:
#   order_items -> products   : INNER JOIN
#     Reason: need product_category_name_english to GROUP BY category.
#             Items with no matching product have no category and are useless here.
#   order_items -> reviews    : INNER JOIN
#     Reason: limiting analysis to reviewed orders only.
#             Orders without a review cannot contribute a satisfaction score.
#             Note: revenue totals here represent reviewed orders only, not total revenue.

# 4. Observations and Assumptions
# - Revenue = SUM(price) from order_items, not payment_value.
# - latest_review CTE resolves multi-review fan-out.
# - INNER JOIN to reviews intentionally excludes unreviewed orders.
# - Total revenue per category will be lower than actual total if many orders in that category were not reviewed.

# - Products with no specific product_category (NULL) have ignored. 

# product_category, total_revenue, total_orders, avg_review_score
#             NULL,   '178285.52', 		 '1439', 			'3.84'


# ============================================================
# Step 1 : Revenue and Average Review Score by Category
# ============================================================

drop table if exists product_summary_revenue;
create table product_summary_revenue
WITH total_revenue AS (
    SELECT ROUND(SUM(price), 2) AS grand_total
    FROM `olist_order_items_dataset_staging_2`
)
SELECT
    p.product_category_name_english                 	AS product_category,
    COUNT(DISTINCT oi.order_id)                     	AS total_orders,
        ROUND(SUM(oi.price), 2)                     	AS total_revenue,
    ROUND(SUM(oi.price) / t.grand_total * 100, 2)   	AS revenue_pct
FROM `olist_order_items_dataset_staging_2`          AS oi
JOIN `olist_products_dataset_staging_2`             AS p  ON oi.product_id = p.product_id
CROSS JOIN total_revenue                            AS t
WHERE p.product_category_name_english IS NOT NULL
GROUP BY p.product_category_name_english, t.grand_total
ORDER BY total_revenue DESC;


# ==================================================================
# Step 2 and 3 : Worst Satisfaction-to-Revenue Ratio (Combined Rank)
# ==================================================================

#  combined_rank = revenue_rank + low_score_rank
#  Lowest combined_rank = simultaneously high revenue and low satisfaction = worst ratio.
drop table if exists product_summary_review;
create table product_summary_review

WITH latest_review AS (
    SELECT
        order_id,
        review_score,
        ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY review_creation_date DESC) AS rn
    FROM `olist_order_reviews_dataset_staging_2`
),
category_metrics AS (
    SELECT
        p.product_category_name_english         AS product_category,
        ROUND(SUM(oi.price), 2)                 AS total_revenue,
        COUNT(DISTINCT oi.order_id)             AS total_orders,
        ROUND(AVG(r.review_score), 2)           AS avg_review_score
    FROM `olist_order_items_dataset_staging_2`      AS oi
    JOIN `olist_products_dataset_staging_2`         AS p  ON oi.product_id = p.product_id
    JOIN latest_review                              AS r  ON oi.order_id   = r.order_id AND r.rn = 1
    WHERE p.product_category_name_english IS NOT NULL
    GROUP BY p.product_category_name_english
)
SELECT
    product_category,
    total_revenue,
    total_orders,
    avg_review_score,
    RANK() OVER (ORDER BY total_revenue DESC)       AS revenue_rank,
    RANK() OVER (ORDER BY avg_review_score ASC)     AS low_score_rank,
    RANK() OVER (ORDER BY total_revenue DESC)
        + RANK() OVER (ORDER BY avg_review_score ASC) AS combined_rank
FROM category_metrics
ORDER BY combined_rank ASC;


# 5. Conclusion
# Categories with the lowest combined_rank are high-revenue and low-satisfaction simultaneously.
# These are the categories where Olist has the most to gain from quality improvement.

# Top 5 Product Categories by revenue
# 1. 'health_beauty'		2. 'watches_gifts'		3. 'bed_bath_table'
# 4. 'sports_leisure' 		5. 'computers_accessories'

# Lowest Combined Rank
# 1. bed_bath_table			2. office_furniture		3. furniture_decor
# 4. computers_accessories	5. watches_gifts

# 'watches_gifts', 'bed_bath_table' and 'computers_accessories' generate most profit and lowest review_scores.
# Prioritize above categories may lead to better review_scores.

