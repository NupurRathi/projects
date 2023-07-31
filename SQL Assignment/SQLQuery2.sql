
-----------------------------------------------Business Growth-----------------------------------------------------
--- Average active users in each year-- 

with active_users as (
	select 
		year(o.order_purchase_timestamp) as purchase_year,
		month(o.order_purchase_timestamp) as purchase_month,
		count(distinct c.customer_id) as total_customers
	from orders o
	left join customers c 
	on c.customer_id = o.customer_id
	group by year(o.order_purchase_timestamp),month(o.order_purchase_timestamp)
)
, average_monthly_users_by_purchase_year as 
(
select 
	purchase_year, 
	avg(total_customers) as average_monthly_users
from active_users
group by purchase_year
)

--- Monthly average order value in each year-- 
,monthly_orders as (
	select 
		year(o.order_purchase_timestamp) as purchase_year,
		month(o.order_purchase_timestamp) as purchase_month,
		sum(p.payment_value) as total_amount
	from orders o
	JOIN order_payments p
		ON o.order_id = p.order_id
	group by year(o.order_purchase_timestamp),month(o.order_purchase_timestamp)
)
, average_monthly_order_value_by_purchase_year as 
(
select 
	purchase_year, 
	round(avg(total_amount),2) as average_monthly_order_value
from monthly_orders
group by purchase_year
)

--------Average Order Value per Customer in each year ------------------------
,aov as(
	SELECT
        year(o.order_purchase_timestamp) AS purchase_year,
		c.customer_unique_id AS customer,
        sum(p.payment_value) AS customer_ordervalue
    FROM customers c
    JOIN orders o
        ON c.customer_id=o.customer_id
	JOIN order_payments p
		ON o.order_id = p.order_id
    GROUP BY year(o.order_purchase_timestamp),c.customer_unique_id
	)
, average_order_value_by_purchase_year as
(
select	
	purchase_year,
	round(avg(customer_ordervalue),2) as avg_order_value
from aov
group by purchase_year
)
---------Average New Customers in each year------
, first_order as (
select 
	 year(o.order_purchase_timestamp) AS purchase_year,
	  customer_unique_id as customer, 
	   min(order_purchase_timestamp) as first_order_date	
from customers c
JOIN orders o
ON c.customer_id=o.customer_id
group by year(o.order_purchase_timestamp),customer_unique_id
)
, new_customers_by_purchase_year as
(
select 
	purchase_year,
	count(customer) as new_customers
from first_order
group by purchase_year
)

---------Average Repeat Customers in each year------
,repeat_orders as (
	select 
		year(o.order_purchase_timestamp) AS purchase_year,
		customer_unique_id as customer
	from customers c
	JOIN orders o
	ON c.customer_id=o.customer_id
	group by year(o.order_purchase_timestamp),customer_unique_id 
	having count(order_id) >1
)
, repeat_customers_by_purchase_year as
(
select purchase_year, 
		count(distinct customer) as repeat_customers
from repeat_orders
group by purchase_year
)

---------------------------Combine business growth-----------------
--Combine all the information together by purchase year
SELECT
	amupy.purchase_year,
	amupy.average_monthly_users,
	amovpy.average_monthly_order_value,
	aovpy.avg_order_value as average_order_value_per_customer,
	ncpy.new_customers,
	rcpy.repeat_customers

FROM average_monthly_users_by_purchase_year AS amupy
JOIN average_order_value_by_purchase_year AS aovpy ON amupy.purchase_year = aovpy.purchase_year
JOIN new_customers_by_purchase_year AS ncpy ON amupy.purchase_year = ncpy.purchase_year
JOIN average_monthly_order_value_by_purchase_year AS amovpy ON amupy.purchase_year = amovpy.purchase_year
JOIN repeat_customers_by_purchase_year AS rcpy ON amupy.purchase_year = rcpy.purchase_year;


------------------------------------Payment Ananlysis-------
select payment_type,
		year(o.order_purchase_timestamp) AS purchase_year,
		count(o.order_id) as total_orders
from orders o
join order_payments op
ON o.order_id = op.order_id
group by payment_type,year(o.order_purchase_timestamp)
order by 2;


-----------------------------------------Product Analysis-------------------------------------
--total revenue each year
with total_revenue as 
(
SELECT
	year(o.order_purchase_timestamp) AS purchase_year,
	SUM(oi.price + oi.freight_value) AS revenue
FROM orders AS o
JOIN order_items AS oi ON oi.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY year(o.order_purchase_timestamp)
),
--total canceled order each year
total_canceled AS
(
SELECT
	year(order_purchase_timestamp) AS purchase_year,
	COUNT(order_id) AS canceled_order
FROM orders
WHERE order_status = 'canceled'
GROUP BY year(order_purchase_timestamp)
),
--Fetch product category name that give total most revenue each year
top_revenue AS
(
SELECT
	purchase_year,
	top_revenue,
	top_product_revenue
FROM(SELECT
		year(o.order_purchase_timestamp) AS purchase_year,
	 	p.product_category_name AS top_revenue,
	 	SUM(price + freight_value) AS top_product_revenue,
	 	RANK() OVER(PARTITION BY year(o.order_purchase_timestamp)
				    ORDER BY SUM(oi.price + oi.freight_value) DESC
					) AS rank
	 FROM orders AS o
	 JOIN order_items AS oi ON oi.order_id = o.order_id
	 JOIN product AS p ON p.product_id = oi.product_id
	 WHERE order_status = 'delivered'
	 GROUP BY year(o.order_purchase_timestamp), p.product_category_name
	 ) AS subq
WHERE rank = 1
),
--Fetch product category name with total most cancel order each year.
top_canceled AS
(
SELECT
	purchase_year,
	top_canceled,
	top_product_canceled
FROM(SELECT
		year(o.order_purchase_timestamp) AS purchase_year,
	 	p.product_category_name AS top_canceled,
	 	COUNT(o.order_id) AS top_product_canceled,
	 	RANK() OVER(PARTITION BY YEAR(order_purchase_timestamp)
				    ORDER BY COUNT(o.order_id) DESC
					) AS rank
	 FROM orders AS o
	 JOIN order_items AS oi ON oi.order_id = o.order_id
	 JOIN product AS p ON p.product_id = oi.product_id
	 WHERE order_status = 'canceled'
	 GROUP BY year(o.order_purchase_timestamp), p.product_category_name
	 ) AS subq
WHERE rank = 1
)
--Combine all the information together by year
SELECT
	torev.purchase_year,
	tr.top_revenue as top_product_category ,
	round(tr.top_product_revenue,2) as top_product_revenue,
	round(torev.revenue,2) AS total_revenue,
	tc.top_canceled,
	tc.top_product_canceled,
	tocan.canceled_order AS total_canceled
FROM total_revenue AS torev
JOIN total_canceled AS tocan ON tocan.purchase_year = torev.purchase_year
JOIN top_revenue AS tr ON tr.purchase_year = torev.purchase_year
JOIN top_canceled AS tc ON tc.purchase_year = torev.purchase_year;