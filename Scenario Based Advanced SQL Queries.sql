-----------------------------DATA PREPARATION-------------------------------------------------


-- Implementing a transaction level table from product level table 

/* 
Making a product level sales table as it contains product related info i.e all the products that are purchased in one transaction 
hence there are multiple rows per trasaction_id in Online_Sales table. 

There are 4 more tables:

gstdetails- carrying gst pct for each product category ,
discount_coupon- the disc offered in each month to specific product categories
marketing_spend- carrying daily marketing spend info
customers- customers demographic details

In the code below we used online_sales,gstdetails and discount_coupon to calculate revenue from each product i.e product level sales.
*/ 

select * into Prod_level_sales from
(select *,iif(coupon_status= 'Used',(Avg_Price*Quantity)*(1-(Discount_pct/100))*(1+gst),(Avg_Price*Quantity)*(1+gst)) as product_total    
from(
select s.*,t.gst,dc.Coupon_Code,Discount_pct from Online_Sales s join gstdetails t on t.Product_Category=s.Product_Category
left join discount_coupon dc on (s.mnth=dc.mnth) and (s.product_category=dc.product_category)
) as t
) as newtable

/* 
Using the prod_level_sales table we now create a view for our transaction level data i.e one row per transaction with invoice.
*/

create view trans_level as
select *, (total_amt+ delivery_charge) as invoice
from (select customerid, transaction_id,transaction_date, STRING_AGG(product_category,',') prod_cat,STRING_AGG(product_description,',') as prod_purch
,sum(product_total) as total_amt, max(Delivery_Charges) as delivery_charge from Prod_level_sales
group by customerid, transaction_id,transaction_date) as t



-- Handling some discrepancy in data i.e there are products on which no discount was offered (as verified from discount table) yet 
-- for those products there are records (in prod_level_sales table) for which coupon_status is entered as 'Used'. 
-- So i will be replacing those records by 'Not Used'.

update Prod_level_sales 
set Coupon_Status= 'Not Used'
where Discount_pct is null and Coupon_Status='Used'


/* Now we have separate dataset for transaction level sales and product level sales  */


----------------SCENARIO BASED ADVANCED SQL QUESTIONS-----------------------

-- Only these 4 datasets are used in each scenarios: 
---- 1. transaction level sales (trans_level)
---- 2. Product level sales     (prod_level_sales)
---- 3. Marketing spend         (marketing_spend)     
---- 4. Customers               (customers)
--The data we have is from 1 jan 2019 to 31 dec 2019.


/* Scenario-1
Say you are working in an ecommerce company as DA, your manager asks you to 
find out the top 10 popular products (product_description) in last 2 months in each of the location.    */

select * from
	(select * , ROW_NUMBER() over(partition by Location order by Units_sold desc) as rank_   
     from    
		(select [Location], Product_Description, sum(quantity) as Units_Sold 
		 from
		   	(select s.*, c.Location 
			 from Prod_level_sales s join customers c on c.CustomerID=s.CustomerID
			 where Transaction_Date > DATEADD(month,-2, (select max(transaction_date) from Prod_level_sales)) 
									) as t1
		 group by [Location], Product_Description
					) as t2
		) as t3
where rank_<=10



/* Scenario-2
After performing statistical analysis (chi-2 test), the product team found that the observed and expected frequency (total orders)
between gender and the product category was significantly different. So for post hoc analysis they need you to 
retrieve no of times customers (based on gender) opted to use which coupon_code and avg discount pct offered corresponding to each product category.

*/

select  product_category,Coupon_Code, gender, count(*) as Coupon_count, AVG(discount_pct) as Avg_disc_pct
from 
(select distinct s.*, c.Gender from prod_level_sales s join Customers c on c.CustomerID=s.CustomerID) as t
where Coupon_Status='Used'
group by product_category,Coupon_Code, gender
order by Product_Category,gender,Coupon_Code, Coupon_count desc


/* Scenario-3
The acquisition team needs a report with key performance metrics to assess the overall marketing performance. 
So find out the no of new customers we have gained on daily basis throught the year. Also calculate the marketing efficiency
ratio and customer acquisition cost.
*/

with cte1 as
(
select *, (total_spend/customers_gained) as Customer_Acquisition_Cost
	from(
		select t2.*, (m.Offline_Spend + m.Online_Spend) total_spend 
			from (
					select first_day as day_, count(customerid) as Customers_gained 
						from(
							select customerid, min(transaction_date) first_day from trans_level
							group by customerid
												) as t1
		group by first_day
							) as t2 
join Marketing_Spend m on m.[Date]=t2.day_ ) as t3
),
cte2 as
(select transaction_date, sum(invoice) as total_rev from trans_level
group by transaction_date)

select transaction_date,customers_gained,total_spend, customer_acquisition_cost,(total_rev/total_spend) as Marketing_Efficiency_Ratio
from
(select * from cte1 join cte2 on cte1. day_=cte2.transaction_date
) as t3



/* Scenario-4
The manager needs to know consistently active customers so find the customers who have made a purchase every month for the last six months.

*/
select c.*,t.mnths_active from Customers c join
(select customerid, count(distinct month(transaction_date)) as mnths_active from trans_level
where transaction_date > DATEADD(month, -6, (select max(transaction_date) from trans_level))
group by  customerid
having count(distinct month(transaction_date)) = 6
) as t on c.CustomerID=t.customerid



/* Scenario-5
You are asked to find out top 5 customers from california who purchased more volume of 'Maze Pen' (Most pop product in cal) than its avg. 
Also calculate the quantity purchased by them on weekend as well as on weekdays. 
*/
with cte1 as
(select * from (
select *, ROW_NUMBER() over(order by vol_purchased desc) as rank_ from (
select c.CustomerID, sum(quantity) as Vol_purchased from Prod_level_sales s join Customers c on c.CustomerID=s.CustomerID 
where Location='California' and Product_Description='Maze Pen' 
group by c.CustomerID
having sum(quantity) >(select avg(quantity) from 
							Prod_level_sales s1 join Customers c1 on c1.CustomerID=s1.CustomerID 
							where c1.location='California' and s1.Product_Description='Maze Pen')
) as t1) as t2
where rank_<=5
),
weekend_ as(
select cte1.CustomerID, sum(quantity) as weekend_vol 
from prod_level_sales s right join cte1 on cte1.CustomerID=s.CustomerID  join Customers c on c.CustomerID= s.CustomerID
where (format(s.Transaction_Date, 'ddd') in ('Sun','Sat')) and (c.location='California') and (s.Product_Description='Maze Pen')  
group by cte1.CustomerID
),
weekdays_ as(
select cte1.CustomerID, sum(quantity) as weekday_vol 
from prod_level_sales s right join cte1 on cte1.CustomerID=s.CustomerID  join Customers c on c.CustomerID= s.CustomerID
where (format(s.Transaction_Date, 'ddd') not in ('Sun','Sat')) and (c.location='California') and (s.Product_Description='Maze Pen')  
group by cte1.CustomerID
)
select a.CustomerID,a.Vol_purchased,isnull(b.weekend_vol,0) as weekend_vol,isnull(c.weekday_vol,0) as weekday_vol from 
cte1 a left join weekend_ b on a.CustomerID=b.CustomerID left join weekdays_ c on a.customerid=c.CustomerID


