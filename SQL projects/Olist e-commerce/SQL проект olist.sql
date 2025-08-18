-- 1. Топ 10 категорий товаров, требующих в среднем наибольшее время для доставки, а также средняя разница между реальной и ожидаемой датами доставки

WITH delivery AS (SELECT 
        pcnt.product_category_name_english as category,
        ROUND(AVG(julianday(o.order_delivered_customer_date) - julianday(o.order_purchase_timestamp))) as avg_days_del,
        ROUND(AVG(julianday(o.order_estimated_delivery_date) - julianday(o.order_delivered_customer_date))) as diff_real_exp
    FROM orders o
    INNER JOIN order_items oi ON o.order_id = oi.order_id
    INNER JOIN products p ON oi.product_id = p.product_id
    INNER JOIN product_category_name_translation pcnt ON p.product_category_name = pcnt.product_category_name
    GROUP BY pcnt.product_category_name_english)
SELECT category AS 'Категория товаров', avg_days_del AS 'Среднее время доставки (дни)', diff_real_exp AS 'Средняя разница между реальной и ожидаемой датой доставки (дни)'
FROM delivery
ORDER BY avg_days_del DESC
LIMIT 10

-- Наиболее часто среди категорий встречаются различные виды мебели, видимо, габариты данной категории требуют большего времени на поиск соответсвующего транспорта, а также этот транспорт оказывается менее быстрым
-- Также можно отметить, что компании предподчитают устанавливать ожидаемую дату доставки с "запасом", так как клиенты более положительно реагирубт на товар более ранюю доставку, чем на позднюю


-- 2. Какие продавцы имеют наибольший процент заказов с высокими оценками (4-5) в своем штате?

WITH seller_stat AS (SELECT seller_state, seller_id, good_score, total_orders, 
        ROW_NUMBER() OVER (PARTITION BY seller_state ORDER BY good_score DESC, total_orders DESC) AS state_rank
      FROM (SELECT s.seller_id, 
              ROUND(CAST(COUNT(CASE WHEN review_score>=4 THEN 1 END) AS real)/COUNT(*)*100, 2) AS good_score,
              seller_state,
              COUNT(*) as total_orders
            FROM order_items oi
            INNER JOIN sellers s ON oi.seller_id=s.seller_id
            LEFT JOIN order_reviews ore ON oi.order_id=ore.order_id
            GROUP BY s.seller_id))
SELECT * 
FROM seller_stat
WHERE state_rank<=3

-- Я присвоила свой номер* каждому продавцу внутри каждого штата по убыванию процента хороших отзывов у них и количеству заказов, так как в случае, если первый пармаетр совпадает у многих, второй может оказаться более надежным показателем качества товара
-- *использую ROW_NUMBER(), а не RANK(), чтобы сделать таблицу более компактной, с RANK() для некоторых штатов выводится более 10 продавцов


-- 3. Каков средний интервал между повторными заказами для клиентов, сделавших более 1 заказа?

WITH customer_stat AS (SELECT customer_unique_id, order_id, order_purchase_timestamp,
    LEAD(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS next_order_date
    FROM customers c
    JOIN orders o ON c.customer_id=o.customer_id)
SELECT customer_unique_id, ROUND(AVG(julianday(next_order_date)-julianday(order_purchase_timestamp))) AS 'Средний интервал между повторными заказами'
FROM customer_stat
WHERE next_order_date IS NOT NULL
GROUP BY customer_unique_id

-- Средний интервал между заказами по всем клиентам?

WITH customer_stat AS (SELECT customer_unique_id, order_id, order_purchase_timestamp,
    LEAD(order_purchase_timestamp) OVER (PARTITION BY customer_unique_id ORDER BY order_purchase_timestamp) AS next_order_date
    FROM customers c
    JOIN orders o ON c.customer_id=o.customer_id)
SELECT ROUND(AVG(julianday(next_order_date)-julianday(order_purchase_timestamp))) AS 'Усредненный интервал между повторными заказами'
FROM customer_stat
WHERE next_order_date IS NOT NULL


-- 4. Процент клиентов, совершивших более одного заказа у продавца?

SELECT seller_id, ROUND(CAST(COUNT(CASE WHEN interactions>1 THEN 1 END) AS REAL)/COUNT(*)*100, 2) AS return_rate
FROM (SELECT c.customer_unique_ID, oi.seller_id, COUNT(*) as interactions
    FROM orders o
    INNER JOIN customers c ON o.customer_id=c.customer_id
    INNER JOIN order_items oi ON o.order_id=oi.order_id
    GROUP BY c.customer_unique_ID, oi.seller_id)
GROUP BY seller_id
HAVING return_rate>0
ORDER BY return_rate DESC


-- 5. Как меняется средний чек заказов по месяцам и как каждый месяц соотносится с предыдущим?

WITH monthly AS (SELECT strftime('%Y-%m', order_purchase_timestamp) AS order_month,
        ROUND(SUM(payment_value), 2) AS total_revenue,
        COUNT(o.order_id) AS order_count,
        ROUND(SUM(payment_value)/COUNT(o.order_id), 2) AS avg_payment
    FROM orders o
    INNER JOIN order_payments p ON o.order_id=p.order_id
    GROUP BY order_month)
SELECT order_month, avg_payment,
    LAG(avg_payment, 1) OVER (ORDER BY order_month) AS prev_avg,
    ROUND(avg_payment - LAG(avg_payment, 1) OVER (ORDER BY order_month), 2) AS monthly_change,
    ROUND((avg_payment - LAG(avg_payment, 1) OVER (ORDER BY order_month))/LAG(avg_payment, 1) OVER (ORDER BY order_month)*100, 2) AS percent_change
FROM monthly
ORDER BY order_month