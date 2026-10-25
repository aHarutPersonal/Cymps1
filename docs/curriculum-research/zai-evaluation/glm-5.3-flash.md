# Profit vs. Cash: Same Business, Different Stories

Model: glm-5.3-flash

## Explanation

Profit and cash measure different things, and this eight-transaction case proves it. Under accrual accounting, revenue is recognized when goods are delivered, not when cash arrives. In T4 the business delivers goods sold for $900, so revenue is $900 — even though only $650 was collected and $250 became a receivable. Cost of goods sold follows the delivered goods: the inventory bought in T3 for $600 was an asset, not an expense, until delivery. At T5, $360 of that inventory is consumed, so COGS is $360 and inventory falls to $240. Gross profit is $900 − $360 = $540. Rent of $100 (T6) is the only operating expense, giving operating profit of $540 − $100 = $440. Now compare that to cash. Collections were $650 in T4 plus $150 in T7, but cash also paid for inventory ($600), rent ($100), and the owner's $80 drawings, and it received the owner's $1,000 contribution and the $500 loan. Ending cash is $1,000 + $500 − $600 + $650 − $100 + $150 − $80 = $1,520. Notice how different the two pictures are: cash of $1,520 is far larger than profit of $440, and neither number explains the other. Cash is inflated by financing items — the owner contribution and the loan — which are not revenue because the business earned nothing by receiving them. Drawings reduce cash and equity but are not expenses because they are not costs of running the business. The $250 delivered but uncollected sale means profit exceeds collected cash for that sale, and the unsold $240 of inventory is cash already spent but not yet an expense. The balance sheet confirms the story: assets are $1,520 cash + $100 receivables + $240 inventory = $1,860; liabilities are the $500 loan; equity is $1,000 contributed − $80 drawings + $440 profit = $1,360. Assets ($1,860) equal liabilities plus equity ($500 + $1,360). Profit reflects what the business earned; cash reflects what moved through the bank. Confusing the two leads to serious mistakes.

## Transactions

T1: Owner contributes $1,000 cash: cash rises by $1,000 and equity rises by $1,000. This is financing, not revenue — the business did not earn it.

T2: Business borrows $500 cash: cash rises by $500 and loan principal rises by $500. Financing, not revenue; it must be repaid.

T3: Buys inventory for $600 cash: cash falls by $600 and inventory (an asset) rises by $600. No expense yet — the goods have not been sold.

T4: Delivers goods sold for $900, collecting $650 with $250 on credit: revenue of $900 is earned at delivery. Cash rises $650, receivables rise $250. No profit number changes from the cash split.

T5: The delivered goods cost $360: inventory falls by $360 and COGS of $360 is recognized. This is when part of the inventory purchase becomes an expense.

T6: Pays rent $100 cash: cash falls by $100 and operating expenses rise by $100, reducing profit.

T7: Collects $150 of the receivable: cash rises by $150 and receivables fall by $150. No new revenue — the $900 was already earned in T4.

T8: Owner withdraws $80 cash (drawings): cash falls by $80 and equity falls by $80. Drawings are not expenses and do not touch profit.

## Checked answers

- revenue: 900
- cogs: 360
- gross_profit: 540
- operating_expenses: 100
- operating_profit: 440
- ending_cash: 1520
- receivables: 100
- inventory: 240
- loan_principal: 500
- equity: 1360

## Misconception feedback

Not quite. The $500 loan does not increase profit: it is financing, so it raises cash and loan principal but the business earned nothing by borrowing it. The $150 collected receivable does not increase profit either: the $900 revenue was already fully recognized in T4 when the goods were delivered, so collecting $150 merely converts a receivable into cash and leaves profit unchanged. Only delivery of goods (with its matching cost) and operating expenses like rent move profit in this case.

## Practice

### Exercise 1

Suppose the final $100 of the T4 receivable is collected after T8, with all costs unchanged. What happens to revenue, profit, cash, and receivables?

Hint: Ask yourself: was this revenue already earned back in T4, or is it earned only when the cash arrives?

Solution: Revenue stays $900 and operating profit stays $440 — the sale was already earned at delivery in T4. Ending cash rises by $100 to $1,620, and receivables fall from $100 to $0. Collection just moves an amount from one asset (receivables) to another (cash); it creates no new profit.

### Exercise 2

The business buys another $120 of inventory for cash, and none of it is sold by period end. Explain why this purchase does not reduce this period's profit.

Hint: Under the stated conventions, when does inventory become an expense — at purchase, or at delivery to a customer?

Solution: The $120 purchase is an exchange of one asset for another: cash falls by $120 and inventory rises by $120. Under accrual accounting, inventory is an asset until the goods are delivered to a customer; only then does its cost become COGS. Since none of the new goods were sold, no expense is recognized and profit is unchanged at $440 — even though cash falls to $1,400. Spending cash is not the same as incurring an expense.
